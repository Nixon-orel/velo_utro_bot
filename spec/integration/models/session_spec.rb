require 'integration_helper'

RSpec.describe Session do
  it 'creates one session when initial updates arrive concurrently', :concurrent do
    ready = Queue.new
    gate = Queue.new
    sessions = Queue.new
    errors = Queue.new

    threads = 4.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          gate.pop
          sessions << described_class.load('501')
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

    captured_errors = errors.size.times.map { queue_pop(errors) }
    expect(captured_errors).to be_empty,
                               captured_errors.map { |error| "#{error.class}: #{error.message}" }.join("\n")
    expect(described_class.where(user_id: '501').count).to eq(1)
    expect(threads.count.times.map { queue_pop(sessions).id }.uniq.one?).to be(true)
  end

  it 'reads and repairs accessors safely when legacy data is nil' do
    session = described_class.create!(user_id: '502', data: nil)

    expect(session.state).to be_nil
    expect(session.new_event).to eq({})

    session.state = 'choose_date'
    session.new_event = { 'author_id' => 42 }
    session.save!

    expect(session.reload).to have_attributes(state: 'choose_date')
    expect(session.new_event).to eq('author_id' => 42)
  end
end
