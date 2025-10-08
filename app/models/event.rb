require 'active_support/time'

class Event < ActiveRecord::Base
  belongs_to :author, class_name: 'User', foreign_key: 'author_id'
  has_and_belongs_to_many :participants, 
                          class_name: 'User', 
                          join_table: 'participants',
                          foreign_key: 'event_id',
                          association_foreign_key: 'user_id'
  
  validates :date, :time, :event_type, :location, :author_id, presence: true
  
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
  
  def self.for_date(date)
    where(date: date).order(:time)
  end
  
  def self.for_period(start_date, end_date)
    where(date: start_date..end_date).order(:date, :time)
  end
  
  def self.upcoming
    where('date >= ?', Date.today).order(:date, :time)
  end
  
  def self.today
    where(date: Date.today).order(:time)
  end
  
  def self.tomorrow
    where(date: Date.tomorrow).order(:time)
  end
  
  def self.this_week
    where(date: Date.today..(Date.today + 7)).order(:date, :time)
  end
  
  def self.next_24_hours
    timezone = ENV['TIMEZONE'] || 'Europe/Moscow'
    tz = ActiveSupport::TimeZone[timezone]
    
    now_utc = Time.now.utc
    end_time_utc = now_utc + 24.hours
    now_local = now_utc.in_time_zone(timezone)
    end_time_local = end_time_utc.in_time_zone(timezone)
    
    puts "Looking for events between #{now_local} (#{now_utc} UTC) and #{end_time_local} (#{end_time_utc} UTC)"
    
    events = []
    
    start_date = now_utc.to_date - 1.day
    end_date = end_time_utc.to_date + 1.day
    
    (start_date..end_date).each do |date|
      puts "Checking date: #{date}"
      date_events = where(date: date).order(:time)
      puts "Found #{date_events.count} events on #{date}"
      
      date_events.each do |event|
        begin
          event_datetime_local = tz.parse("#{event.date} #{event.time}")
          event_datetime_utc = event_datetime_local.utc
          
          puts "Event: #{event.event_type} at #{event_datetime_local} local (#{event_datetime_utc} UTC) from input '#{event.date} #{event.time}'"
          puts "Comparing UTC times: event #{event_datetime_utc} >= now #{now_utc}: #{event_datetime_utc >= now_utc}"
          puts "Comparing UTC times: event #{event_datetime_utc} <= end #{end_time_utc}: #{event_datetime_utc <= end_time_utc}"
          
          if event_datetime_utc >= now_utc && event_datetime_utc <= end_time_utc
            puts "Adding event to list (UTC comparison passed)"
            events << event
          else
            puts "Event does not match UTC time criteria"
          end
        rescue => e
          puts "Error parsing event time: #{e.message} for event #{event.id} with time '#{event.time}'"
        end
      end
    end
    
    puts "Total events found: #{events.count}"
    events.sort_by { |event| [event.date, event.time] }
  end
  
  def has_participant?(user)
    participants.include?(user)
  end
  
  def participants_list
    participants.map(&:display_name).join(', ')
  end
  
  def static?
    @static_events ||= ENV['STATIC_EVENTS'].to_s.split(',').map(&:strip)
    @static_events.include?(event_type)
  end
  
  def channel_link
    return nil unless channel_message_id
    
    channel_id = ENV['PUBLIC_CHANNEL_ID']
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
    if weather_data.present?
      history = weather_history || []
      history << {
        timestamp: Time.current,
        weather_data: weather_data
      }
      self.weather_history = history
    end
    
    self.weather_data = new_data
    self.weather_updated_at = Time.current
    save!
  end
  
  def weather_city_or_default
    weather_city.presence || ENV['DEFAULT_WEATHER_CITY'] || 'Orel'
  end
end