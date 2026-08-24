require 'integration_helper'

RSpec.describe Events::PublishEvent do
  let(:author) { create_user(telegram_id: 1) }
  let(:event) { create_event(author: author, published: false) }
  let(:payload) { { text: 'Event', parse_mode: 'HTML' } }

  it 'marks the event published only after Telegram returns a message id' do
    gateway = RecordingTelegramGateway.new(message_id: 321)
    AppClock.source = -> { Time.utc(2026, 8, 22, 12, 0) }

    result = described_class.call(
      event: event,
      actor: author,
      gateway: gateway,
      channel_id: '@veloutro',
      payload: payload
    )

    expect(result).to be_success
    expect(event.reload).to have_attributes(
      published: true,
      channel_message_id: 321,
      published_at: AppClock.now
    )
    expect(gateway.messages).to eq([{ chat_id: '@veloutro', **payload }])
  end

  it 'leaves the event unpublished when Telegram delivery fails' do
    gateway = RecordingTelegramGateway.new(error: Faraday::TimeoutError.new('timeout'))

    result = described_class.call(
      event: event,
      actor: author,
      gateway: gateway,
      channel_id: '@veloutro',
      payload: payload
    )

    expect(result).to be_failure
    expect(result.error_code).to eq(:delivery_failed)
    expect(event.reload).to have_attributes(
      published: false,
      channel_message_id: nil,
      published_at: nil
    )
  end

  it 'does not deliver an already published event again' do
    gateway = RecordingTelegramGateway.new(message_id: 321)

    first = described_class.call(
      event: event,
      actor: author,
      gateway: gateway,
      channel_id: '@veloutro',
      payload: payload
    )
    second = described_class.call(
      event: event,
      actor: author,
      gateway: gateway,
      channel_id: '@veloutro',
      payload: payload
    )

    expect(first).to be_success
    expect(second).to be_failure
    expect(second.error_code).to eq(:already_published)
    expect(gateway.messages.count).to eq(1)
  end

  it 'rejects publication by another user before Telegram delivery' do
    stranger = create_user(telegram_id: 2)
    gateway = RecordingTelegramGateway.new

    result = described_class.call(
      event: event,
      actor: stranger,
      gateway: gateway,
      channel_id: '@veloutro',
      payload: payload
    )

    expect(result).to be_failure
    expect(result.error_code).to eq(:forbidden)
    expect(gateway.messages).to be_empty
  end

  it 'rejects an empty channel before Telegram delivery' do
    gateway = RecordingTelegramGateway.new

    result = described_class.call(
      event: event,
      actor: author,
      gateway: gateway,
      channel_id: nil,
      payload: payload
    )

    expect(result).to be_failure
    expect(result.error_code).to eq(:channel_not_configured)
    expect(gateway.messages).to be_empty
  end

  it 'delivers once when two publication requests race', :concurrent do
    entered = Queue.new
    release = Queue.new
    gateway = CoordinatedTelegramGateway.new(entered: entered, release: release)
    event_id = event.id
    actor_id = author.id
    results = Queue.new
    errors = Queue.new

    publish = lambda do
      ActiveRecord::Base.connection_pool.with_connection do
        results << described_class.call(
          event: Event.find(event_id),
          actor: User.find(actor_id),
          gateway: gateway,
          channel_id: '@veloutro',
          payload: payload
        )
      end
    rescue => e
      errors << e
    end

    threads = [Thread.new(&publish)]
    begin
      queue_pop(entered)
      second_backend_pid = Queue.new
      threads << Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          second_backend_pid << connection.raw_connection.backend_pid
          results << described_class.call(
            event: Event.find(event_id),
            actor: User.find(actor_id),
            gateway: gateway,
            channel_id: '@veloutro',
            payload: payload
          )
        end
      rescue => e
        errors << e
      end
      wait_for_database_lock(queue_pop(second_backend_pid))
    ensure
      release << true
      join_threads(threads)
    end

    raise errors.pop unless errors.empty?

    publication_results = 2.times.map { queue_pop(results) }
    expect(publication_results.count(&:success?)).to eq(1)
    expect(publication_results.map(&:error_code)).to contain_exactly(nil, :already_published)
    expect(gateway.messages.count).to eq(1)
    expect(Event.find(event_id)).to be_published
  end

  class CoordinatedTelegramGateway
    attr_reader :messages

    def initialize(entered:, release:)
      @entered = entered
      @release = release
      @messages = []
      @mutex = Mutex.new
    end

    def send_message(**attributes)
      first_delivery = @mutex.synchronize do
        @messages << attributes
        @messages.one?
      end
      if first_delivery
        @entered << true
        Timeout.timeout(TestConcurrency::TIMEOUT_SECONDS) { @release.pop }
      end

      Telegram::Bot::Types::Message.new(
        message_id: 321,
        date: 1_777_030_400,
        chat: Telegram::Bot::Types::Chat.new(id: -100_123, type: 'channel')
      )
    end
  end

end
