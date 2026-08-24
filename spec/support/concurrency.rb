require 'timeout'

module TestConcurrency
  TIMEOUT_SECONDS = 5

  def queue_pop(queue)
    Timeout.timeout(TIMEOUT_SECONDS) { queue.pop }
  end

  def join_threads(threads)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + TIMEOUT_SECONDS
    unfinished = threads.reject do |thread|
      remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
      remaining.positive? && thread.join(remaining)
    end

    return if unfinished.empty?

    threads.select(&:alive?).each(&:kill)
    threads.each(&:join)

    raise Timeout::Error, 'Concurrent test threads did not finish in time'
  ensure
    threads.each(&:value) if defined?(unfinished) && unfinished&.empty?
  end

  def wait_for_database_lock(backend_pid)
    Timeout.timeout(TIMEOUT_SECONDS) do
      loop do
        wait_event_type = ActiveRecord::Base.connection.select_value(
          "SELECT wait_event_type FROM pg_stat_activity WHERE pid = #{Integer(backend_pid)}"
        )
        break if wait_event_type == 'Lock'

        sleep 0.01
      end
    end
  end
end

RSpec.configure do |config|
  config.include TestConcurrency
end
