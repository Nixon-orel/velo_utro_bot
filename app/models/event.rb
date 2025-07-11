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
    now = Time.now.in_time_zone(timezone)
    end_time = now + 24.hours
    
    puts "Looking for events between #{now} and #{end_time}"
    
    events = []
    
    (now.to_date..end_time.to_date).each do |date|
      puts "Checking date: #{date}"
      date_events = where(date: date).order(:time)
      puts "Found #{date_events.count} events on #{date}"
      
      date_events.each do |event|
        begin
          hour, minute = event.time.split(':').map(&:to_i)
          event_datetime = Time.parse("#{event.date} #{event.time}").in_time_zone(timezone)
          puts "Event: #{event.event_type} at #{event_datetime} (from #{event.date} #{event.time}), now: #{now}, end: #{end_time}"
          puts "Conditions: >= now: #{event_datetime >= now}, <= end: #{event_datetime <= end_time}"
          
          if event_datetime >= now && event_datetime <= end_time
            puts "Adding event to list"
            events << event
          else
            puts "Event does not match time criteria"
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
end