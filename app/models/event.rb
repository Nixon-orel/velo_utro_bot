require 'active_support/time'

class Event < ActiveRecord::Base
  WEATHER_SCHEDULE_ATTRIBUTES = %w[date time latitude longitude published].freeze

  belongs_to :author, class_name: 'User', foreign_key: 'author_id'
  has_many :notification_deliveries, dependent: :delete_all
  has_and_belongs_to_many :participants, 
                          class_name: 'User', 
                          join_table: 'participants',
                          foreign_key: 'event_id',
                          association_foreign_key: 'user_id'
  
  validates :date, :time, :event_type, :location, :author_id, presence: true
  validate :supported_time_format
  before_update :advance_weather_schedule_revision, if: :weather_schedule_changed?
  
  def formatted_time
    time
  end
  
  def formatted_date
    day = date.day
    month_genitive = I18n.t('date.genitive_month_names')[date.month]
    year = date.year
    "#{day} #{month_genitive} #{year}"
  end

  def formatted_date_short
    date.strftime('%d.%m.%Y')
  end
  
  def self.on_date(date)
    where(date: date).order(:time)
  end
  
  def self.from_date_through(start_date, end_date)
    where(date: start_date..end_date).order(:date, :time)
  end

  def self.for_date(date)
    on_date(date)
  end

  def self.for_period(start_date, end_date)
    from_date_through(start_date, end_date)
  end
  
  def self.upcoming(now: AppClock.now)
    select_upcoming(where('date >= ?', now.to_date).order(:date, :time), now: now)
  end

  def self.upcoming_for_author(user, now: AppClock.now)
    events = user.authored_events.where('date >= ?', now.to_date).order(:date, :time)
    select_upcoming(events, now: now)
  end

  def self.upcoming_for_participant(user, now: AppClock.now)
    events = user.events_as_participant.where('date >= ?', now.to_date).order(:date, :time)
    select_upcoming(events, now: now)
  end

  def self.upcoming_on_date(date, now: AppClock.now)
    select_upcoming(on_date(date), now: now)
  end

  def self.upcoming_from_date_through(start_date, end_date, now: AppClock.now)
    select_upcoming(from_date_through(start_date, end_date), now: now)
  end

  def self.next_24_hours(now: AppClock.now)
    ends_at = now + 24.hours
    select_upcoming(from_date_through(now.to_date, ends_at.to_date), now: now)
      .take_while { |event| event.starts_at <= ends_at }
  end
  
  def self.tomorrow
    on_date(AppClock.today + 1.day)
  end
  
  def self.this_week
    from_date_through(AppClock.today, AppClock.today + 6.days)
  end
  
  def starts_at
    EventTime.parse(date: date, time: time)
  end
  
  def has_participant?(user)
    participants.include?(user)
  end
  
  def participants_list
    participants.map(&:display_name).join(', ')
  end
  
  def static?
    APP_CONFIG.static_events.include?(event_type)
  end
  
  def channel_link
    return nil unless channel_message_id
    
    channel_id = APP_CONFIG.public_channel_id
    return nil unless channel_id
    
    if channel_id.start_with?('@')
      channel_username = channel_id[1..-1]
      "https://t.me/#{channel_username}/#{channel_message_id}"
    elsif channel_id.start_with?('-100')
      clean_channel_id = channel_id[4..-1]
      "https://t.me/c/#{clean_channel_id}/#{channel_message_id}"
    else
      nil
    end
  end
  
  def weather
    weather_data || {}
  end
  
  def weather_changed_significantly?(new_weather)
    return true if weather.empty?
    
    old_weather = weather
    
    temp_changed = (new_weather['temp_c'].to_f - old_weather['temp_c'].to_f).abs > 5
    
    old_precip = old_weather['precip_prob'].to_i > 50
    new_precip = new_weather['precip_prob'].to_i > 50
    precip_changed = old_precip != new_precip
    
    wind_changed = (new_weather['wind_kph'].to_f - old_weather['wind_kph'].to_f).abs > 10
    
    alerts_appeared = !new_weather['alerts'].to_a.empty? && old_weather['alerts'].to_a.empty?
    
    temp_changed || precip_changed || wind_changed || alerts_appeared
  end
  
  def update_weather_data(new_data)
    new_data = Weather::Forecast.normalize(new_data)

    if weather_data.present?
      history = weather_history || []
      history << {
        timestamp: AppClock.now,
        weather_data: weather_data
      }
      self.weather_history = history
    end
    
    self.weather_data = new_data
    self.weather_updated_at = AppClock.now
    save!
  end
  
  def weather_city_or_default
    weather_city.presence || APP_CONFIG.default_weather_city
  end

  private

  def self.select_upcoming(events, now:)
    events.filter_map do |event|
      starts_at = event.starts_at
      [starts_at, event] if starts_at && starts_at >= now
    end.sort_by(&:first).map(&:last)
  end
  private_class_method :select_upcoming

  def supported_time_format
    return if EventTime.valid_input?(time)
    return if persisted? && !will_save_change_to_time? && EventTime.parse(date: date, time: time)

    errors.add(:time, :invalid)
  end

  def weather_schedule_changed?
    WEATHER_SCHEDULE_ATTRIBUTES.any? { |attribute| will_save_change_to_attribute?(attribute) }
  end

  def advance_weather_schedule_revision
    self.weather_schedule_revision = weather_schedule_revision.to_i + 1
  end
end
