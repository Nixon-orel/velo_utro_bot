require 'active_support/time'

class Event < ActiveRecord::Base
  belongs_to :author, class_name: 'User', foreign_key: 'author_id'
  has_and_belongs_to_many :participants, 
                          class_name: 'User', 
                          join_table: 'participants',
                          foreign_key: 'event_id',
                          association_foreign_key: 'user_id'
  
  validates :date, :time, :event_type, :location, :author_id, presence: true
  validate :supported_time_format
  
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
  
  def self.upcoming
    where('date >= ?', AppClock.today)
      .order(:date, :time)
      .select { |event| event.starts_at && event.starts_at >= AppClock.now }
  end
  
  def self.today
    on_date(AppClock.today)
  end
  
  def self.tomorrow
    on_date(AppClock.today + 1.day)
  end
  
  def self.this_week
    from_date_through(AppClock.today, AppClock.today + 6.days)
  end
  
  def self.next_24_hours
    now_local = AppClock.now
    end_time_local = now_local + 24.hours
    
    AppLogger.debug('Event', 'Looking for events in next 24 hours', from: now_local, to: end_time_local)
    
    candidates = from_date_through(now_local.to_date, end_time_local.to_date)
    events = candidates.select do |event|
      event.starts_at && event.starts_at >= now_local && event.starts_at <= end_time_local
    end
    
    AppLogger.debug('Event', 'Selected events in next 24 hours', events_count: events.count)
    events.sort_by { |event| [event.date, event.time] }
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

  def supported_time_format
    return if EventTime.valid_input?(time)
    return if persisted? && !will_save_change_to_time? && EventTime.parse(date: date, time: time)

    errors.add(:time, :invalid)
  end
end
