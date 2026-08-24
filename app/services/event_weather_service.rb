class EventWeatherService
  def self.create_event_with_weather(session, coordinates, city_name, expected_state: nil)
    require_relative 'weather_service'
    require_relative 'weather_recommendations'
    
    event_date = Date.parse(session.new_event['date'])
    event_time = session.new_event['time']

    weather_data = nil
    result = Events::CreateEvent.from_session(
      session: session,
      expected_state: expected_state
    ) do
      weather_data = fetch_weather(coordinates, event_date, event_time)
      build_weather_attributes(weather_data, coordinates, city_name)
    end
    return result if result.failure?

    event = result.value
    weather_info = build_weather_info(weather_data, event_time, city_name)

    if weather_data
      AppLogger.info('EventWeatherService', 'Event created with weather data', event_id: event.id)
    else
      AppLogger.warn('EventWeatherService', 'Event created without weather data', event_id: event.id)
    end

    ServiceResult.success(
      event,
      weather_available: !weather_data.nil?,
      weather_info: weather_info
    )
  rescue Date::Error, TypeError => e
    ServiceResult.failure(:invalid_date, error: e)
  rescue => e
    AppLogger.error('EventWeatherService', 'Failed before event persistence', exception: e)
    ServiceResult.failure(:weather_preparation_failed, error: e)
  end

  def self.update_event_weather(event:, actor:, coordinates:, city_name:)
    return ServiceResult.failure(:forbidden) unless Events::Policy.manage?(event: event, actor: actor)

    weather_data = fetch_weather(coordinates, event.date, event.time)
    lat, lon = coordinates.split(',')
    result = Events::EditEvent.call(
      event: event,
      actor: actor,
      changes: {
        weather_city: city_name,
        latitude: lat.to_f,
        longitude: lon.to_f,
        weather_data: weather_data || {},
        weather_updated_at: weather_data ? AppClock.now : nil
      }
    )
    return result if result.failure?

    ServiceResult.success(event, weather_available: !weather_data.nil?)
  rescue => e
    AppLogger.error('EventWeatherService', 'Failed to update event weather', event_id: event.id, exception: e)
    ServiceResult.failure(:weather_update_failed, error: e)
  end
  
  private

  def self.fetch_weather(coordinates, event_date, event_time)
    WeatherService.fetch_weather_for_event(coordinates, event_date, event_time)
  rescue => e
    AppLogger.error('EventWeatherService', 'Weather lookup failed; creating event without weather', exception: e)
    nil
  end
  
  def self.build_weather_attributes(weather_data, coordinates, city_name)
    lat, lon = coordinates.split(',')
    attributes = {
      weather_city: city_name,
      latitude: lat.to_f,
      longitude: lon.to_f
    }
    return attributes unless weather_data

    attributes.merge(
      weather_data: weather_data,
      weather_updated_at: AppClock.now
    )
  end

  def self.build_weather_info(weather_data, event_time, city_name)
    return nil unless weather_data

    recommendations = WeatherRecommendations.generate(weather_data, event_time)
    format_weather_info(weather_data, recommendations, city_name)
  rescue => e
    AppLogger.error('EventWeatherService', 'Failed to format weather information', exception: e)
    nil
  end
  
  def self.format_weather_info(weather_data, recommendations, city_name)
    temp = weather_data['temp_c']
    feels_like = weather_data['feelslike_c']
    condition = weather_data['condition']
    wind_speed = weather_data['wind_kph']
    precip_prob = weather_data['precip_prob']
    is_fallback = weather_data['is_fallback']
    fallback_from = weather_data['fallback_from']
    
    weather_text = if city_name == I18n.t('custom_coordinates')
      "🌤️ Погода по координатам:\n#{condition}, #{temp}°C"
    else
      "🌤️ Погода в г. #{city_name}:\n#{condition}, #{temp}°C"
    end
    
    if is_fallback && fallback_from
      weather_text += "\n⚠️ (приблизительно, данные за #{fallback_from})"
    end
    
    weather_text += " (ощущ. #{feels_like}°C)" if feels_like && feels_like != temp
    weather_text += "\n💨 Ветер: #{wind_speed} км/ч" if wind_speed
    weather_text += "\n☔ Вероятность осадков: #{precip_prob}%" if precip_prob
    
    if recommendations && recommendations.any?
      weather_text += "\n\n⚡ Рекомендации:"
      recommendations.first(3).each { |rec| weather_text += "\n• #{rec}" }
    end
    
    weather_text
  end
  
end
