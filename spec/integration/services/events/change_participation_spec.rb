require 'integration_helper'

RSpec.describe Events::ChangeParticipation do
  it 'joins once when the same callback is delivered repeatedly' do
    author = create_user(telegram_id: 1)
    participant = create_user(telegram_id: 2)
    event = create_event(author: author)

    first = described_class.call(event: event, actor: participant, join: true)
    second = described_class.call(event: event, actor: participant, join: true)

    expect(first).to be_success
    expect(first.metadata).to include(changed: true, participating: true)
    expect(second).to be_success
    expect(second.metadata).to include(changed: false, participating: true)
    expect(event.participants.reload).to contain_exactly(participant)
  end

  it 'removes an existing participant' do
    author = create_user(telegram_id: 1)
    participant = create_user(telegram_id: 2)
    event = create_event(author: author)
    event.participants << participant

    result = described_class.call(event: event, actor: participant, join: false)

    expect(result).to be_success
    expect(result.metadata).to include(changed: true, participating: false)
    expect(event.participants.reload).to be_empty
  end

  it 'rejects a missing actor' do
    author = create_user(telegram_id: 1)
    event = create_event(author: author)

    result = described_class.call(event: event, actor: nil, join: true)

    expect(result).to be_failure
    expect(result.error_code).to eq(:invalid_actor)
    expect(event.participants).to be_empty
  end

  it 'keeps one participant when concurrent join requests race', :concurrent do
    author = create_user(telegram_id: 1)
    participant = create_user(telegram_id: 2)
    event = create_event(author: author)
    gate = Queue.new
    results = Queue.new
    errors = Queue.new

    ready = Queue.new
    threads = 4.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          gate.pop
          results << described_class.call(
            event: Event.find(event.id),
            actor: User.find(participant.id),
            join: true
          )
        end
      rescue => e
        errors << e
      end
    end
    begin
      threads.count.times { queue_pop(ready) }
    ensure
      threads.count.times { gate << true }
      join_threads(threads)
    end

    raise errors.pop unless errors.empty?

    participation_results = threads.count.times.map { queue_pop(results) }
    expect(participation_results).to all(be_success)
    expect(participation_results.count { |result| result.metadata[:changed] }).to eq(1)
    expect(Event.find(event.id).participants).to contain_exactly(participant)
  end

  it 'reports one change when concurrent unjoin requests reach the same participant row', :concurrent do
    author = create_user(telegram_id: 1)
    participant = create_user(telegram_id: 2)
    event = create_event(author: author)
    event.participants << participant
    lock_ready = Queue.new
    release_lock = Queue.new
    request_ready = Queue.new
    request_gate = Queue.new
    backend_pids = Queue.new
    results = Queue.new
    errors = Queue.new

    locker = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        connection.transaction do
          connection.execute(
            "SELECT 1 FROM participants WHERE event_id = #{event.id} AND user_id = #{participant.id} FOR UPDATE"
          )
          lock_ready << true
          queue_pop(release_lock)
        end
      end
    rescue => e
      errors << e
    end

    threads = []
    begin
      queue_pop(lock_ready)
      threads = 2.times.map do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do |connection|
            backend_pids << connection.raw_connection.backend_pid
            request_ready << true
            request_gate.pop
            results << described_class.call(
              event: Event.find(event.id),
              actor: User.find(participant.id),
              join: false
            )
          end
        rescue => e
          errors << e
        end
      end
      threads.count.times { queue_pop(request_ready) }
      threads.count.times { request_gate << true }
      threads.count.times { wait_for_database_lock(queue_pop(backend_pids)) }
    ensure
      threads.count.times { request_gate << true }
      release_lock << true
      join_threads([locker, *threads])
    end

    raise errors.pop unless errors.empty?

    participation_results = threads.count.times.map { queue_pop(results) }
    expect(participation_results).to all(be_success)
    expect(participation_results.count { |result| result.metadata[:changed] }).to eq(1)
    expect(Event.find(event.id).participants).to be_empty
  end
end
