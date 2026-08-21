module AppClock
  class << self
    attr_writer :source

    def now
      raw_time = @source ? @source.call : Time.now
      raw_time.in_time_zone(APP_CONFIG.timezone)
    end

    def utc_now
      now.utc
    end

    def today
      now.to_date
    end

    def reset!
      @source = nil
    end
  end
end
