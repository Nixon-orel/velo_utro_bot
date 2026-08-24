require 'time'
require_relative 'weather/forecast'

class WeatherRecommendations
  def self.generate(weather_data, event_time = nil)
    return [] if weather_data.nil? || weather_data.empty?

    weather_data = Weather::Forecast.normalize(weather_data)
    
    recommendations = []
    feels_like = weather_data['feelslike_c'].to_f
    wind_speed = weather_data['wind_kph'].to_f
    precip_prob = weather_data['precip_prob'].to_i
    precip_mm = weather_data['precip_mm'].to_f
    condition = weather_data['condition'].to_s.downcase
    
    recommendations.concat(temperature_recommendations(feels_like))
    recommendations.concat(precipitation_recommendations(precip_prob, precip_mm, condition))
    recommendations.concat(wind_recommendations(wind_speed))
    recommendations.concat(time_recommendations(weather_data, event_time))
    recommendations.concat(alert_recommendations(weather_data['alerts']))
    
    recommendations.uniq.compact
  end
  
  private
  
  def self.temperature_recommendations(feels_like)
    recommendations = []
    effective_temp = feels_like
    
    case effective_temp
    when ...0
      recommendations << "🥶 Мороз! Полная зимняя экипировка"
      recommendations << "⚠️ Осторожно - возможен гололед!"
    when 0...5
      recommendations << "🧥 Термобелье и непродуваемая куртка"
      recommendations << "🧤 Зимние перчатки обязательны"
      recommendations << "👂 Защита для ушей"
    when 5...15
      recommendations << "🧥 Ветровка или жилет"
      recommendations << "🧤 Легкие перчатки"
      recommendations << "🧣 Бафф на шею"
    when 15...25
      recommendations << "👕 Идеальная погода! Легкая одежда"
    when 25..Float::INFINITY
      recommendations << "💧 Возьмите больше воды"
      recommendations << "☀️ Солнцезащитный крем"
    end
    
    recommendations
  end
  
  def self.precipitation_recommendations(precip_prob, precip_mm, condition)
    recommendations = []
    
    if precip_prob > 70 || precip_mm > 0.5
      recommendations << "☔ Дождевик обязателен"
      recommendations << "⚠️ Осторожно на поворотах и спусках"
    elsif precip_prob > 30
      recommendations << "☔ Возьмите дождевик на всякий случай"
    end
    
    if condition.include?('туман')
      recommendations << "🔦 Мощный задний фонарь"
      recommendations << "🔆 Яркая одежда"
    end
    
    recommendations
  end
  
  def self.wind_recommendations(wind_speed)
    recommendations = []
    
    case wind_speed
    when 10..20
      recommendations << "💨 Ветровка пригодится"
      recommendations << "🗺️ Планируйте маршрут с учетом ветра"
    when 20..30
      recommendations << "💨 Сильный ветер! Будьте осторожны"
      recommendations << "🧥 Непродуваемая куртка"
    when 30..Float::INFINITY
      recommendations << "⚠️ ОПАСНЫЙ ветер!"
    end
    
    recommendations
  end
  
  def self.time_recommendations(weather_data, event_time)
    recommendations = []
    sunset = weather_data['sunset']
    return recommendations unless event_time && sunset
    
    begin
      start_time = event_time.to_s.strip.split(/\s*-\s*/, 2).first
      return recommendations unless start_time.match?(/\A(?:[01]?\d|2[0-3]):[0-5]\d\z/)

      event_hour, event_minute = start_time.split(':').map(&:to_i)
      sunset_time = Time.strptime(sunset, '%I:%M %p')
      event_minutes = event_hour * 60 + event_minute
      sunset_minutes = sunset_time.hour * 60 + sunset_time.min
      
      if event_minutes >= sunset_minutes - 120
        recommendations << "🔦 Фонари обязательны (скоро темно)"
        recommendations << "🔆 Светоотражающие элементы"
      elsif event_hour <= 6
        recommendations << "🔦 Фонари для утренней поездки"
        recommendations << "🔆 Светоотражающие элементы"
      end
    rescue ArgumentError
      # Игнорируем ошибки парсинга времени
    end
    
    recommendations
  end
  
  def self.alert_recommendations(alerts)
    return [] if alerts.nil? || alerts.empty?
    
    recommendations = []
    alerts.each do |alert|
      case alert['event']&.downcase
      when /wind/, /ветер/
        recommendations << "💨 Штормовое предупреждение по ветру!"
      when /rain/, /дождь/
        recommendations << "🌧️ Штормовое предупреждение по осадкам!"
      when /snow/, /снег/
        recommendations << "❄️ Предупреждение о снегопаде!"
      when /ice/, /лед/, /гололед/
        recommendations << "🧊 Предупреждение о гололеде!"
      else
        recommendations << "⚠️ Погодное предупреждение!"
      end
    end
    
    recommendations
  end
end
