class EventWeatherService
  def self.create_event_with_weather(session, coordinates, city_name)
    require_relative 'weather_service'
    require_relative 'weather_recommendations'
    
    event_date = Date.parse(session.new_event['date'])
    event_time = session.new_event['time']
    
    begin
      weather_data = WeatherService.fetch_weather_for_event(coordinates, event_date, event_time)
      
      if weather_data
        lat, lon = coordinates.split(',')
        
        event = create_event(session, {
          weather_city: city_name,
          latitude: lat.to_f,
          longitude: lon.to_f,
          weather_data: weather_data,
          weather_updated_at: Time.current
        })
        
        schedule_weather_updates(event)
        
        recommendations = WeatherRecommendations.generate(weather_data, event_time)
        weather_info = format_weather_info(weather_data, recommendations, city_name)
        
        puts "[EventWeatherService] Event #{event.id} created successfully with weather data"
        { success: true, event: event, weather_info: weather_info }
      else
        event = create_event(session)
        puts "[EventWeatherService] Event #{event.id} created without weather data (API unavailable)"
        { success: false, event: event, weather_info: nil }
      end
    rescue => e
      puts "[EventWeatherService] Error creating event with weather: #{e.message}"
      puts e.backtrace.first(3).join("\n") if ENV['WEATHER_DEBUG'] == 'true'
      
      event = create_event(session)
      { success: false, event: event, weather_info: nil, error: e.message }
    end
  end
  
  private
  
  def self.create_event(session, weather_attrs = {})
    event_attrs = {
      date: Date.parse(session.new_event['date']),
      time: session.new_event['time'],
      event_type: session.new_event['type'],
      location: session.new_event['location'],
      distance: session.new_event['distance'],
      pace: session.new_event['pace'],
      track: session.new_event['track'],
      map: session.new_event['map'],
      additional_info: session.new_event['additional_info'],
      author_id: session.new_event['author_id']
    }
    
    event_attrs.merge!(weather_attrs)
    event = Event.new(event_attrs)
    event.save
    event
  end
  
  def self.format_weather_info(weather_data, recommendations, city_name)
    temp = weather_data[:temp_c] || weather_data['temp_c']
    feels_like = weather_data[:feelslike_c] || weather_data['feelslike_c']
    condition = weather_data[:condition] || weather_data['condition']
    wind_speed = weather_data[:wind_kph] || weather_data['wind_kph']
    precip_prob = weather_data[:precip_prob] || weather_data['precip_prob']
    
    weather_text = if city_name == I18n.t('custom_coordinates')
      "🌤️ Погода по координатам:\n#{condition}, #{temp}°C"
    else
      "🌤️ Погода в г. #{city_name}:\n#{condition}, #{temp}°C"
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
  
  def self.schedule_weather_updates(event)
    require_relative '../bot/helpers/weather_scheduler'
    Bot::Helpers::WeatherScheduler.schedule_weather_updates(event)
  end
end