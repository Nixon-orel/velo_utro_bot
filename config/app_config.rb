class AppConfig
  class InvalidConfiguration < StandardError; end

  DEFAULT_TIMEZONE = 'Europe/Moscow'
  DEFAULT_WEATHER_COORDINATES = '52.9651,36.0785'
  DEFAULT_WEATHER_CITY_NAME = 'Орёл'

  ENV_KEYS = %w[
    TG_TOKEN
    PUBLIC_CHANNEL_ID
    BOT_USERNAME
    WEBHOOK_DOMAIN
    ADMIN_IDS
    STATIC_EVENTS
    DAILY_ANNOUNCEMENT_ENABLED
    DAILY_ANNOUNCEMENT_TIME
    MONTHLY_STATS_DAY
    TIMEZONE
    WEATHER_API_KEY
    WEATHER_ENABLED
    DEFAULT_WEATHER_COORDINATES
    DEFAULT_WEATHER_CITY_NAME
    DEFAULT_WEATHER_CITY
    WEATHER_ADMIN_ALERTS
    WEATHER_DEBUG
    PORT
  ].freeze

  def self.load(root:, env: ENV)
    environment = env.fetch('RACK_ENV', 'development')
    path = File.join(root, 'config', 'environments', "#{environment}.yml")
    yaml_values = File.exist?(path) ? YAML.load_file(path, aliases: true) : {}
    env_values = ENV_KEYS.each_with_object({}) do |key, values|
      values[key] = env[key] if env.key?(key)
    end

    new(yaml_values.merge(env_values).merge('RACK_ENV' => environment))
  end

  def initialize(values)
    @values = values.transform_keys(&:to_s)
    normalize!
    validate!
    @values.freeze
  end

  def [](key)
    @values[key.to_s]
  end

  def to_h
    @values.dup
  end

  def environment
    self['RACK_ENV']
  end

  def production?
    environment == 'production'
  end

  def telegram_token
    self['TG_TOKEN']
  end

  def public_channel_id
    self['PUBLIC_CHANNEL_ID']
  end

  def bot_username
    self['BOT_USERNAME']
  end

  def admin_ids
    self['ADMIN_IDS']
  end

  def static_events
    self['STATIC_EVENTS']
  end

  def event_types
    self['EVENT_TYPES']
  end

  def daily_announcement_enabled?
    self['DAILY_ANNOUNCEMENT_ENABLED']
  end

  def daily_announcement_time
    self['DAILY_ANNOUNCEMENT_TIME']
  end

  def monthly_stats_day
    self['MONTHLY_STATS_DAY']
  end

  def timezone
    self['TIMEZONE']
  end

  def weather_api_key
    self['WEATHER_API_KEY']
  end

  def weather_enabled?
    self['WEATHER_ENABLED']
  end

  def default_weather_coordinates
    self['DEFAULT_WEATHER_COORDINATES']
  end

  def default_weather_city
    self['DEFAULT_WEATHER_CITY_NAME']
  end

  def weather_admin_alerts?
    self['WEATHER_ADMIN_ALERTS']
  end

  def weather_debug?
    self['WEATHER_DEBUG']
  end

  def port
    self['PORT']
  end

  private

  def normalize!
    @values['ADMIN_IDS'] = list(@values['ADMIN_IDS'])
    @values['STATIC_EVENTS'] = list(@values['STATIC_EVENTS'])
    @values['EVENT_TYPES'] = Array(@values['EVENT_TYPES']).map(&:to_s).freeze
    @values['DAILY_ANNOUNCEMENT_ENABLED'] = boolean(@values['DAILY_ANNOUNCEMENT_ENABLED'])
    @values['DAILY_ANNOUNCEMENT_TIME'] = presence(@values['DAILY_ANNOUNCEMENT_TIME']) || '08:00'
    @values['MONTHLY_STATS_DAY'] = normalize_monthly_stats_day(@values['MONTHLY_STATS_DAY'])
    @values['TIMEZONE'] = presence(@values['TIMEZONE']) || DEFAULT_TIMEZONE
    @values['WEATHER_ENABLED'] = boolean(@values['WEATHER_ENABLED'])
    @values['WEATHER_ADMIN_ALERTS'] = boolean(@values['WEATHER_ADMIN_ALERTS'])
    @values['WEATHER_DEBUG'] = boolean(@values['WEATHER_DEBUG'])
    @values['DEFAULT_WEATHER_COORDINATES'] = presence(@values['DEFAULT_WEATHER_COORDINATES']) || DEFAULT_WEATHER_COORDINATES
    @values['DEFAULT_WEATHER_CITY_NAME'] = presence(@values['DEFAULT_WEATHER_CITY_NAME']) ||
                                            presence(@values['DEFAULT_WEATHER_CITY']) ||
                                            DEFAULT_WEATHER_CITY_NAME
    @values['PORT'] = (presence(@values['PORT']) || 4567).to_i
  end

  def validate!
    unless ActiveSupport::TimeZone[timezone]
      raise InvalidConfiguration, "Unknown TIMEZONE: #{timezone}"
    end

    return if daily_announcement_time.match?(/\A(?:[01]\d|2[0-3]):[0-5]\d\z/)

    raise InvalidConfiguration, 'DAILY_ANNOUNCEMENT_TIME must use HH:MM format'
  end

  def list(value)
    items = value.is_a?(Array) ? value : value.to_s.split(',')
    items.map { |item| item.to_s.strip }.reject(&:empty?).freeze
  end

  def boolean(value)
    value == true || value.to_s.casecmp('true').zero?
  end

  def presence(value)
    value unless value.nil? || value.to_s.strip.empty?
  end

  def normalize_monthly_stats_day(value)
    return nil unless presence(value)

    value.to_i.clamp(1, 28)
  end
end
