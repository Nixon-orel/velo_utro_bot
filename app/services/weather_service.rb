require 'faraday'
require 'json'

class WeatherService
  API_BASE_URL = 'http://api.weatherapi.com/v1'
  
  def self.fetch_weather_for_event(coordinates, event_date, event_time, retry_count = 0)
    api_key = ENV['WEATHER_API_KEY']
    unless api_key
      log_error("Weather API key not configured", { coordinates: coordinates })
      return nil
    end
    
    clean_coordinates = coordinates.gsub(/\s+/, '')
    
    url = "#{API_BASE_URL}/forecast.json?key=#{api_key}&q=#{clean_coordinates}&days=14&aqi=no&lang=ru"
    
    response = connection.get(url)
    
    if response.success?
      data = JSON.parse(response.body)
      result = parse_response_for_event(data, event_date, event_time)
      log_success("Weather data fetched successfully", { coordinates: coordinates })
      result
    else
      error_msg = "API returned status #{response.status}"
      error_data = {
        coordinates: coordinates,
        status: response.status,
        body: response.body[0..500],
        retry_count: retry_count
      }
      
      if retry_count < 2 && [429, 500, 502, 503, 504].include?(response.status)
        sleep(2 ** retry_count)
        log_warning("Retrying weather API request", error_data)
        return fetch_weather_for_event(coordinates, event_date, event_time, retry_count + 1)
      end
      
      log_error(error_msg, error_data)
      nil
    end
  rescue Faraday::TimeoutError => e
    error_data = { coordinates: coordinates, retry_count: retry_count, error: e.class.name }
    
    if retry_count < 2
      sleep(2 ** retry_count)
      log_warning("Retrying after timeout", error_data)
      return fetch_weather_for_event(coordinates, event_date, event_time, retry_count + 1)
    end
    
    log_error("Weather API timeout after retries", error_data)
    nil
  rescue JSON::ParserError => e
    log_error("Invalid JSON response from weather API", {
      coordinates: coordinates,
      error: e.message,
      response_body: response&.body&.[](0..500)
    })
    nil
  rescue => e
    log_error("Unexpected weather API error", {
      coordinates: coordinates,
      error: e.class.name,
      message: e.message,
      retry_count: retry_count
    })
    nil
  end
  
  private
  
  def self.parse_response_for_event(data, event_date, event_time)
    event_date_str = event_date.is_a?(Date) ? event_date.strftime('%Y-%m-%d') : event_date
    event_hour = event_time.split(':')[0].to_i
    
    forecast_day = data['forecast']['forecastday'].find { |day| day['date'] == event_date_str }
    return nil unless forecast_day
    
    hourly_forecast = forecast_day['hour'].find { |hour| hour['time'].include?("#{event_hour.to_s.rjust(2, '0')}:") }
    hourly_forecast ||= forecast_day['hour'][event_hour] if forecast_day['hour'][event_hour]
    
    if hourly_forecast
      {
        temp_c: hourly_forecast['temp_c'],
        feelslike_c: hourly_forecast['feelslike_c'],
        condition: hourly_forecast['condition']['text'],
        condition_icon: hourly_forecast['condition']['icon'],
        wind_kph: hourly_forecast['wind_kph'],
        wind_dir: hourly_forecast['wind_dir'],
        precip_mm: hourly_forecast['precip_mm'],
        precip_prob: hourly_forecast['chance_of_rain'],
        humidity: hourly_forecast['humidity'],
        uv: hourly_forecast['uv'],
        sunrise: forecast_day['astro']['sunrise'],
        sunset: forecast_day['astro']['sunset'],
        alerts: data['alerts'] || [],
        forecast_date: event_date_str,
        forecast_time: event_time
      }
    else
      day_data = forecast_day['day']
      {
        temp_c: day_data['avgtemp_c'],
        feelslike_c: day_data['avgtemp_c'],
        condition: day_data['condition']['text'],
        condition_icon: day_data['condition']['icon'],
        wind_kph: day_data['maxwind_kph'],
        wind_dir: 'N/A',
        precip_mm: day_data['totalprecip_mm'],
        precip_prob: day_data['daily_chance_of_rain'],
        humidity: day_data['avghumidity'],
        uv: day_data['uv'],
        sunrise: forecast_day['astro']['sunrise'],
        sunset: forecast_day['astro']['sunset'],
        alerts: data['alerts'] || [],
        forecast_date: event_date_str,
        forecast_time: event_time
      }
    end
  end
  
  def self.get_fallback_weather(event)
    return nil unless event.weather_history.is_a?(Array) && !event.weather_history.empty?
    
    latest_weather = event.weather_history.last
    if latest_weather && latest_weather['updated_at']
      updated_at = Time.parse(latest_weather['updated_at'])
      if Time.now - updated_at < 48.hours
        log_warning("Using fallback weather data", {
          event_id: event.id,
          fallback_age_hours: ((Time.now - updated_at) / 1.hour).round(1)
        })
        return latest_weather['data']
      end
    end
    
    nil
  rescue => e
    log_error("Error retrieving fallback weather", {
      event_id: event.id,
      error: e.message
    })
    nil
  end

  def self.log_success(message, data = {})
    puts "[WeatherService][SUCCESS] #{message} #{data.to_json}" if ENV['WEATHER_DEBUG'] == 'true'
  end

  def self.log_warning(message, data = {})
    puts "[WeatherService][WARNING] #{message} #{data.to_json}"
    notify_admin_if_needed(:warning, message, data)
  end

  def self.log_error(message, data = {})
    puts "[WeatherService][ERROR] #{message} #{data.to_json}"
    notify_admin_if_needed(:error, message, data)
  end

  def self.notify_admin_if_needed(level, message, data)
    return unless ENV['WEATHER_ADMIN_ALERTS'] == 'true'
    return unless CONFIG['ADMIN_USER_IDS']
    
    if level == :error || (level == :warning && should_alert_warning?(message, data))
      require_relative '../bot/helpers/weather_admin_notifier'
      Bot::Helpers::WeatherAdminNotifier.send_alert(level, message, data)
    end
  rescue => e
    puts "[WeatherService] Failed to send admin alert: #{e.message}"
  end

  def self.should_alert_warning?(message, data)
    return true if message.include?('timeout') && data[:retry_count] >= 1
    return true if message.include?('Retrying') && data[:retry_count] >= 1
    false
  end

  def self.connection
    @connection ||= Faraday.new(url: API_BASE_URL) do |faraday|
      faraday.request :url_encoded
      faraday.adapter Faraday.default_adapter
      faraday.options.timeout = 10
    end
  end
  
end