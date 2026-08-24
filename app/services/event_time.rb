class EventTime
  INPUT_FORMAT = /\A(?:[01]\d|2[0-3]):[0-5]\d\z/
  LEGACY_START_FORMAT = /\A(?:[01]?\d|2[0-3]):[0-5]\d\z/

  def self.valid_input?(value)
    value.to_s.strip.match?(INPUT_FORMAT)
  end

  def self.parse(date:, time:, timezone: APP_CONFIG.timezone)
    date = Date.parse(date.to_s) unless date.is_a?(Date)
    start_time = time.to_s.strip.split(/\s*-\s*/, 2).first
    return nil unless start_time.match?(LEGACY_START_FORMAT)

    hour, minute = start_time.split(':').map(&:to_i)
    ActiveSupport::TimeZone[timezone].local(date.year, date.month, date.day, hour, minute)
  rescue Date::Error, ArgumentError
    nil
  end

  private_class_method :new
end
