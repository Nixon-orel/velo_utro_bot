class WeatherRecommendations
  def self.generate(weather_data, event_time)
    return [] if weather_data.nil? || weather_data.empty?
    
    recommendations = []
    temp = (weather_data[:temp_c] || weather_data['temp_c']).to_f
    feels_like = (weather_data[:feelslike_c] || weather_data['feelslike_c']).to_f
    wind_speed = (weather_data[:wind_kph] || weather_data['wind_kph']).to_f
    precip_prob = (weather_data[:precip_prob] || weather_data['precip_prob']).to_i
    precip_mm = (weather_data[:precip_mm] || weather_data['precip_mm']).to_f
    condition = (weather_data[:condition] || weather_data['condition']).to_s.downcase
    
    recommendations.concat(temperature_recommendations(temp, feels_like))
    recommendations.concat(precipitation_recommendations(precip_prob, precip_mm, condition))
    recommendations.concat(wind_recommendations(wind_speed))
    recommendations.concat(time_recommendations(weather_data, event_time))
    recommendations.concat(alert_recommendations(weather_data[:alerts] || weather_data['alerts']))
    
    recommendations.uniq.compact
  end
  
  private
  
  def self.temperature_recommendations(temp, feels_like)
    recommendations = []
    effective_temp = feels_like
    
    case effective_temp
    when Float::INFINITY..-1
      recommendations << "🥶 Мороз! Полная зимняя экипировка"
      recommendations << "⚠️ Осторожно - возможен гололед!"
    when -1..5
      recommendations << "🧥 Термобелье и непродуваемая куртка"
      recommendations << "🧤 Зимние перчатки обязательны"
      recommendations << "👂 Защита для ушей"
    when 5..15
      recommendations << "🧥 Ветровка или жилет"
      recommendations << "🧤 Легкие перчатки"
      recommendations << "🧣 Бафф на шею"
    when 15..25
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
      recommendations << "🌊 Крылья защитят от брызг"
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
    sunset = weather_data[:sunset] || weather_data['sunset']
    return recommendations unless event_time && sunset
    
    begin
      event_hour = event_time.split(':')[0].to_i
      sunset_hour = sunset.split(':')[0].to_i
      
      if event_hour >= sunset_hour - 2
        recommendations << "🔦 Фонари обязательны (скоро темно)"
        recommendations << "🔆 Светоотражающие элементы"
      elsif event_hour <= 6
        recommendations << "🔦 Фонари для утренней поездки"
        recommendations << "🔆 Светоотражающие элементы"
      end
    rescue
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