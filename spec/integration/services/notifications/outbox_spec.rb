require 'integration_helper'
require 'securerandom'

RSpec.describe Notifications::Outbox do
  it 'rejects a weather delivery without its event' do
    delivery = NotificationDelivery.new(
      notification_type: 'weather.critical_24h',
      context_key: 'event-context',
      idempotency_key: 'weather:missing-event',
      chat_id: '123',
      payload: { text: 'Weather changed' },
      status: 'pending',
      attempts: 0,
      next_attempt_at: AppClock.now
    )

    expect(delivery).not_to be_valid
    expect(delivery.errors[:event]).to be_present
  end

  it 'rejects an unknown delivery type without its event' do
    delivery = NotificationDelivery.new(
      notification_type: 'unknown.system',
      context_key: 'unknown-context',
      idempotency_key: 'unknown:missing-event',
      chat_id: '123',
      payload: { text: 'Unknown notification' },
      status: 'pending',
      attempts: 0,
      next_attempt_at: AppClock.now
    )

    expect(delivery).not_to be_valid
    expect(delivery.errors[:event]).to be_present
  end

  it 'enqueues a recipient batch atomically and reuses existing idempotency keys' do
    author = create_user(telegram_id: 1)
    participant = create_user(telegram_id: 2)
    event = create_event(author: author)
    attributes = [author, participant].map do |user|
      delivery_attributes(event:, user:)
    end

    first_batch = described_class.enqueue!(attributes)
    second_batch = described_class.enqueue!(attributes)

    expect(first_batch.map(&:id)).to eq(second_batch.map(&:id))
    expect(NotificationDelivery.count).to eq(2)
  end

  it 'does not retain part of an invalid recipient batch' do
    author = create_user(telegram_id: 1)
    event = create_event(author: author)
    attributes = [
      delivery_attributes(event:, user: author),
      delivery_attributes(event:, user: author).merge(idempotency_key: nil)
    ]

    expect { described_class.enqueue!(attributes) }
      .to raise_error(ActiveRecord::RecordInvalid)
    expect(NotificationDelivery.count).to eq(0)
  end

  it 'deduplicates the same delivery under concurrent enqueue attempts', :concurrent do
    author = create_user(telegram_id: 1)
    event = create_event(author: author)
    attributes = [delivery_attributes(event: event, user: author)]
    start = Queue.new

    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          start.pop
          described_class.enqueue!(attributes)
        end
      end
    end
    2.times { start << true }
    join_threads(threads)

    expect(NotificationDelivery.count).to eq(1)
  end

  def delivery_attributes(event:, user:)
    {
      event: event,
      recipient: user,
      notification_type: 'weather.critical_24h',
      context_key: 'event-context',
      idempotency_key: "weather:#{event.id}:critical_24h:user:#{user.id}",
      chat_id: user.telegram_id,
      payload: { text: 'Weather changed', parse_mode: 'HTML' }
    }
  end
end

RSpec.describe Notifications::OutboxProcessor do
  before do
    AppClock.source = -> { Time.utc(2026, 8, 24, 9, 0) }
  end

  it 'marks a successful delivery and records its attempt' do
    delivery = create_delivery
    gateway = RecordingTelegramGateway.new

    processed = described_class.new(gateway: gateway).process_due

    expect(processed.map(&:id)).to eq([delivery.id])
    expect(gateway.messages).to contain_exactly(
      chat_id: delivery.chat_id,
      text: 'Weather changed',
      parse_mode: 'HTML'
    )
    expect(delivery.reload).to have_attributes(
      status: 'delivered',
      attempts: 1,
      delivered_at: AppClock.now,
      locked_at: nil,
      last_error: nil
    )
  end

  it 'retains a failed delivery for a delayed retry with error history' do
    delivery = create_delivery
    gateway = RecordingTelegramGateway.new(error: Faraday::TimeoutError.new('timeout'))

    described_class.new(gateway: gateway).process_due

    expect(delivery.reload).to have_attributes(
      status: 'pending',
      attempts: 1,
      next_attempt_at: AppClock.now + 30.seconds,
      locked_at: nil,
      last_error: 'Faraday::TimeoutError: timeout'
    )
    expect(delivery.error_history).to contain_exactly(
      include(
        'at' => AppClock.now.iso8601,
        'error_class' => 'Faraday::TimeoutError',
        'message' => 'timeout'
      )
    )
  end

  it 'filters configured secrets from persisted delivery errors' do
    use_app_config(
      'TG_TOKEN' => 'telegram-secret',
      'WEATHER_API_KEY' => 'weather-secret'
    )
    delivery = create_delivery
    error = Faraday::ConnectionFailed.new(
      'request to /bottelegram-secret/sendMessage?key=weather-secret failed'
    )
    gateway = RecordingTelegramGateway.new(error: error)

    described_class.new(gateway: gateway).process_due

    delivery.reload
    expect(delivery.last_error).to include('[FILTERED]')
    expect(delivery.last_error).not_to include('telegram-secret', 'weather-secret')
    expect(delivery.error_history.to_json).not_to include('telegram-secret', 'weather-secret')
  end

  it 'retries only after the delay and then records success' do
    delivery = create_delivery
    failing_gateway = RecordingTelegramGateway.new(error: Faraday::TimeoutError.new('timeout'))
    described_class.new(gateway: failing_gateway).process_due

    successful_gateway = RecordingTelegramGateway.new
    processor = described_class.new(gateway: successful_gateway)
    expect(processor.process_due).to be_empty

    retry_at = delivery.reload.next_attempt_at
    AppClock.source = -> { retry_at }
    processor.process_due

    expect(successful_gateway.messages.length).to eq(1)
    expect(delivery.reload).to have_attributes(status: 'delivered', attempts: 2)
  end

  it 'moves a delivery to failed after the fifth unsuccessful attempt' do
    delivery = create_delivery(
      attempts: 4,
      error_history: Array.new(4) { { 'message' => 'previous timeout' } }
    )
    gateway = RecordingTelegramGateway.new(error: Faraday::TimeoutError.new('timeout'))

    described_class.new(gateway: gateway).process_due

    expect(delivery.reload).to have_attributes(
      status: 'failed',
      attempts: 5,
      next_attempt_at: nil,
      locked_at: nil
    )
    expect(delivery.error_history.length).to eq(5)
  end

  it 'recovers a delivery whose processing lease expired' do
    delivery = create_delivery(
      status: 'processing',
      locked_at: AppClock.now - 6.minutes,
      lock_token: SecureRandom.uuid
    )
    gateway = RecordingTelegramGateway.new

    described_class.new(gateway: gateway).process_due

    expect(gateway.messages.length).to eq(1)
    expect(delivery.reload.status).to eq('delivered')
  end

  it 'does not take over a delivery with an active processing lease' do
    delivery = create_delivery(
      status: 'processing',
      locked_at: AppClock.now - 1.minute,
      lock_token: SecureRandom.uuid
    )
    gateway = RecordingTelegramGateway.new

    expect(described_class.new(gateway: gateway).process_due).to be_empty
    expect(gateway.messages).to be_empty
    expect(delivery.reload.status).to eq('processing')
  end

  it 'prevents an expired worker from overwriting a replacement lease' do
    stale_worker = create_delivery(
      status: 'processing',
      locked_at: AppClock.now - 6.minutes,
      lock_token: SecureRandom.uuid
    )
    replacement = NotificationDelivery.claim_due(limit: 1).first

    expect(replacement.lock_token).not_to eq(stale_worker.lock_token)
    expect { stale_worker.mark_delivered! }
      .to raise_error(NotificationDelivery::LostLease)
    expect(replacement.reload.status).to eq('processing')
  end

  it 'does not overwrite or crash after losing its lease during Telegram delivery' do
    delivery = create_delivery
    replacement = nil
    messages = []
    gateway = Object.new
    gateway.define_singleton_method(:send_message) do |**attributes|
      messages << attributes
      AppClock.source = -> { Time.utc(2026, 8, 24, 9, 6) }
      replacement = NotificationDelivery.claim_due(limit: 1).first
      true
    end

    expect { described_class.new(gateway: gateway).process_due }.not_to raise_error

    expect(messages.length).to eq(1)
    expect(replacement).to be_present
    expect(delivery.reload).to have_attributes(
      status: 'processing',
      lock_token: replacement.lock_token
    )
  end

  it 'lets only one concurrent processor claim a delivery', :concurrent do
    delivery = create_delivery
    send_started = Queue.new
    release_send = Queue.new
    messages = Queue.new
    gateway = Object.new
    gateway.define_singleton_method(:send_message) do |**attributes|
      messages << attributes
      send_started << true
      release_send.pop
      true
    end
    processors = 2.times.map { described_class.new(gateway: gateway) }

    first_thread = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection { processors.first.process_due }
    end
    queue_pop(send_started)
    second_thread = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection { processors.last.process_due }
    end
    second_thread.join
    release_send << true
    join_threads([first_thread, second_thread])

    expect(messages.size).to eq(1)
    expect(delivery.reload.status).to eq('delivered')
  end

  it 'removes pending deliveries when their event is deleted' do
    delivery = create_delivery

    delivery.event.destroy!

    expect(NotificationDelivery.where(id: delivery.id)).not_to exist
  end

  it 'retains delivery history when its recipient is deleted' do
    delivery = create_delivery
    recipient = create_user(telegram_id: 'departed-user')
    delivery.update!(recipient: recipient)

    recipient.destroy!

    expect(delivery.reload.recipient_id).to be_nil
    expect(delivery.event).to be_present
  end

  def create_delivery(**attributes)
    author = create_user(telegram_id: "user-#{SecureRandom.hex(4)}")
    event = create_event(author: author)
    NotificationDelivery.create!(
      {
        event: event,
        recipient: author,
        notification_type: 'weather.critical_24h',
        context_key: 'event-context',
        idempotency_key: "weather:#{event.id}:critical_24h:user:#{author.id}",
        chat_id: author.telegram_id,
        payload: { text: 'Weather changed', parse_mode: 'HTML' },
        status: 'pending',
        attempts: 0,
        next_attempt_at: AppClock.now
      }.merge(attributes)
    )
  end
end
