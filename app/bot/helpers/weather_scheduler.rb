require 'rufus-scheduler'

module Bot
  module Helpers
    class WeatherScheduler
      @@scheduler = nil
      @@mutex = Mutex.new
      
      def self.start
        return unless ENV['WEATHER_ENABLED'] == 'true'
        
        @@mutex.synchronize do
          stop_internal
          @@scheduler = Rufus::Scheduler.new
          puts "[WeatherScheduler] Started at #{Time.now}"
        end
      end
      
      def self.stop
        stop_internal
      end
      
      def self.schedule_weather_updates(event)
        return unless ENV['WEATHER_ENABLED'] == 'true'
        return unless event.weather_data.present?
        
        start unless @@scheduler
        
        timezone = ENV['TIMEZONE'] || 'Europe/Moscow'
        tz = ActiveSupport::TimeZone[timezone]
        event_datetime = tz.parse("#{event.date} #{event.time}")
        
        schedule_24h_update(event, event_datetime)
        schedule_2h_update(event, event_datetime)
      end
      
      private
      
      def self.stop_internal
        if @@scheduler && !@@scheduler.down?
          @@scheduler.shutdown
          @@scheduler = nil
          puts "[WeatherScheduler] Stopped at #{Time.now}"
        end
      end
      
      def self.schedule_24h_update(event, event_datetime)
        update_time = event_datetime - 24.hours
        return if update_time.utc <= Time.now.utc
        
        @@scheduler.at update_time do
          update_weather_24h_before(event.id)
        end
        
        puts "[WeatherScheduler] Scheduled 24h update for event #{event.id} at #{update_time} (#{update_time.utc} UTC)"
      end
      
      def self.schedule_2h_update(event, event_datetime)
        update_time = event_datetime - 2.hours
        return if update_time.utc <= Time.now.utc
        
        @@scheduler.at update_time do
          update_weather_2h_before(event.id)
        end
        
        puts "[WeatherScheduler] Scheduled 2h update for event #{event.id} at #{update_time} (#{update_time.utc} UTC)"
      end
      
      def self.update_weather_24h_before(event_id)
        begin
          puts "[WeatherScheduler] Running 24h weather update for event #{event_id}"
          
          event = Event.find_by(id: event_id)
          return unless event
          
          check_weather_changes(event, '24h')
        rescue => e
          puts "[WeatherScheduler] Error in 24h update for event #{event_id}: #{e.message}"
        end
      end
      
      def self.update_weather_2h_before(event_id)
        begin
          puts "[WeatherScheduler] Running 2h weather update for event #{event_id}"
          
          event = Event.find_by(id: event_id)
          return unless event
          
          check_weather_changes(event, '2h')
        rescue => e
          puts "[WeatherScheduler] Error in 2h update for event #{event_id}: #{e.message}"
        end
      end
      
      def self.check_weather_changes(event, update_type)
        require_relative '../../services/weather_service'
        require_relative 'weather_notifier'
        
        return unless event && event.latitude && event.longitude
        
        coordinates = "#{event.latitude},#{event.longitude}"
        new_weather = WeatherService.fetch_weather_for_event(coordinates, event.date, event.time)
        
        if new_weather.nil?
          new_weather = WeatherService.get_fallback_weather(event)
          if new_weather.nil?
            puts "[WeatherScheduler] No weather data available for event #{event.id} (#{update_type}), skipping update"
            return
          end
        end
        
        old_weather = event.weather
        
        begin
          if update_type == '24h'
            WeatherNotifier.handle_24h_weather_update(event, old_weather, new_weather)
          elsif update_type == '2h'
            WeatherNotifier.handle_2h_weather_update(event, new_weather)
          end
          
          event.update_weather_data(new_weather)
          puts "[WeatherScheduler] Weather data updated for event #{event.id} (#{update_type})"
        rescue => e
          puts "[WeatherScheduler] Error processing weather notifications for event #{event.id}: #{e.message}"
          puts e.backtrace.first(5).join("\n") if ENV['WEATHER_DEBUG'] == 'true'
        end
      end
    end
  end
end