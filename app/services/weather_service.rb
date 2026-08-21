require_relative 'weather/client'
require_relative 'weather/forecast'
require 'time'

class WeatherService
  class << self
    attr_writer :admin_notifier

    def fetch_weather_for_event(coordinates, event_date, event_time, _retry_count = 0)
      data = client.fetch_forecast(coordinates)
      return nil unless data

      forecast = Weather::Forecast.for_event(
        data: data,
        event_date: event_date,
        event_time: event_time
      )

      if forecast&.fetch('is_fallback', false)
        report(
          :warn,
          'Using fallback weather data for date outside forecast range',
          requested_date: forecast['forecast_date'],
          fallback_date: forecast['fallback_from']
        )
      end

      forecast
    rescue Date::Error, ArgumentError => e
      report(:error, 'Invalid event date or time for weather forecast', error: e.message)
      nil
    end

    def get_fallback_weather(event)
      latest = event.weather_history.to_a.last
      return nil unless latest

      timestamp = latest['timestamp'] || latest['updated_at']
      data = latest['weather_data'] || latest['data']
      return nil unless timestamp && data

      updated_at = Time.parse(timestamp.to_s)
      fallback_age = AppClock.now - updated_at
      return nil unless fallback_age < 48.hours

      report(
        :warn,
        'Using stored fallback weather data',
        event_id: event.id,
        fallback_age_hours: (fallback_age / 1.hour).round(1)
      )
      Weather::Forecast.normalize(data)
    rescue => e
      report(:error, 'Failed to read stored fallback weather data', event_id: event.id, error: e.message)
      nil
    end

    def reset_client!
      @client = nil
    end

    def report(level, message, data = {})
      log_level = level == :error ? :error : level
      AppLogger.public_send(log_level, 'WeatherService', message, **data)
      notify_admin(level, message, data)
    end

    private

    def client
      @client ||= Weather::Client.new(
        api_key: APP_CONFIG.weather_api_key,
        reporter: method(:report)
      )
    end

    def notify_admin(level, message, data)
      return unless APP_CONFIG.weather_admin_alerts?
      return unless @admin_notifier
      return unless level == :error || alert_worthy_warning?(message, data)

      @admin_notifier.send_alert(level, message, data)
    rescue => e
      AppLogger.error('WeatherService', 'Failed to send admin alert', exception: e)
    end

    def alert_worthy_warning?(message, data)
      retry_count = data[:retry_count].to_i
      (message.downcase.include?('timeout') || message.include?('Retrying')) && retry_count >= 1
    end
  end
end
