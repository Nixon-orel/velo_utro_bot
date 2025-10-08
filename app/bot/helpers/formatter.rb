module Bot
  module Helpers
    class Formatter
      def self.format_date(date)
        weekday = I18n.l(date, format: '%A')
        capitalized_weekday = weekday.capitalize
        
        day = date.day
        month_genitive = I18n.t('date.genitive_month_names')[date.month]
        
        "#{capitalized_weekday} (#{day} #{month_genitive})"
      end
      
      def self.format_time(time)
        time.to_s[0..4]
      end
      
      def self.event_info(event)
        participants = event.participants_list
        template = I18n.t('event_info')
        
        event_data = {
          event_type: event.event_type,
          formatted_time: event.formatted_time,
          location: event.location,
          distance: event.distance,
          pace: event.pace,
          track: event.track,
          map: event.map,
          additional_info: event.additional_info,
          author: {
            display_name: event.author.display_name
          }
        }
        
        if event.weather_data.present? && ENV['WEATHER_ENABLED'] == 'true'
          weather_info = format_weather_detailed(event.weather_data, event.weather_city)
          event_data[:weather] = weather_info
        end
        
        Mustache.render(template, {
          title: format_date(event.date),
          event: event_data,
          participants: participants
        })
      end
      
      def self.format_weather(weather_data, city_name = nil)
        return nil unless weather_data.is_a?(Hash)
        
        data = extract_weather_data(weather_data)
        weather_emoji = get_weather_emoji(data[:condition], data[:temp])
        
        weather_text = "#{weather_emoji} #{data[:condition]}, #{data[:temp]}°C"
        weather_text += " (ощущ. #{data[:feels_like]}°C)" if data[:feels_like] && data[:feels_like] != data[:temp]
        
        if data[:wind_speed]
          wind_emoji = get_wind_emoji(data[:wind_speed])
          weather_text += " | #{wind_emoji} #{data[:wind_speed]} км/ч"
        end
        
        if data[:precip_prob] && data[:precip_prob] > 0
          precip_emoji = get_precip_emoji(data[:precip_prob])
          weather_text += " | #{precip_emoji} #{data[:precip_prob]}%"
        end
        
        if data[:humidity] && data[:humidity] > 70
          weather_text += " | 💧 #{data[:humidity]}%"
        end
        
        if data[:uv_index] && data[:uv_index] > 5
          uv_emoji = data[:uv_index] > 8 ? "☢️" : "☀️"
          weather_text += " | #{uv_emoji} УФ #{data[:uv_index]}"
        end
        
        weather_text
      end
      
      def self.format_weather_detailed(weather_data, city_name = nil)
        return nil unless weather_data.is_a?(Hash)
        
        data = extract_weather_data(weather_data)
        weather_emoji = get_weather_emoji(data[:condition], data[:temp])
        
        weather_text = "🌤️ Прогноз погоды:\n"
        weather_text += "#{weather_emoji} #{data[:condition]}, #{data[:temp]}°C"
        weather_text += " (ощущ. #{data[:feels_like]}°C)" if data[:feels_like] && data[:feels_like] != data[:temp]
        
        if data[:wind_speed]
          wind_emoji = get_wind_emoji(data[:wind_speed])
          weather_text += "\n#{wind_emoji} Ветер: #{data[:wind_speed]} км/ч"
        end
        
        if data[:precip_prob] && data[:precip_prob] > 0
          precip_emoji = get_precip_emoji(data[:precip_prob])
          weather_text += "\n#{precip_emoji} Вероятность осадков: #{data[:precip_prob]}%"
        end
        
        if data[:humidity] && data[:humidity] > 70
          weather_text += "\n💧 Влажность: #{data[:humidity]}%"
        end
        
        if data[:uv_index] && data[:uv_index] > 5
          uv_emoji = data[:uv_index] > 8 ? "☢️" : "☀️"
          weather_text += "\n#{uv_emoji} УФ-индекс: #{data[:uv_index]}"
        end
        
        require_relative '../../services/weather_recommendations'
        recommendations = WeatherRecommendations.generate(weather_data, nil)
        
        if recommendations.any?
          weather_text += "\n\n⚡ Рекомендации для велопоездки:"
          recommendations.first(4).each { |rec| weather_text += "\n• #{rec}" }
        end
        
        weather_text
      end
      
      def self.extract_weather_data(weather_data)
        {
          temp: weather_data['temp_c'] || weather_data[:temp_c],
          feels_like: weather_data['feelslike_c'] || weather_data[:feelslike_c],
          condition: weather_data['condition'] || weather_data[:condition],
          wind_speed: weather_data['wind_kph'] || weather_data[:wind_kph],
          precip_prob: weather_data['precip_prob'] || weather_data[:precip_prob],
          humidity: weather_data['humidity'] || weather_data[:humidity],
          uv_index: weather_data['uv'] || weather_data[:uv]
        }
      end
      
      def self.get_weather_emoji(condition, temp)
        return "🌤️" unless condition.is_a?(String)
        
        condition_lower = condition.downcase
        
        return "🌧️" if condition_lower.include?('дождь') || condition_lower.include?('ливень')
        return "⛈️" if condition_lower.include?('гроза') || condition_lower.include?('шторм')
        return "🌨️" if condition_lower.include?('снег') || condition_lower.include?('вьюга')
        return "🌦️" if condition_lower.include?('морось') || condition_lower.include?('изморозь')
        
        return "☀️" if condition_lower.include?('ясно') || condition_lower.include?('солнечно')
        return "⛅" if condition_lower.include?('переменная облачность') || condition_lower.include?('малооблачно')
        return "☁️" if condition_lower.include?('облачно') || condition_lower.include?('пасмурно')
        
        return "🌫️" if condition_lower.include?('туман') || condition_lower.include?('дымка')
        return "💨" if condition_lower.include?('ветрено')
        
        return "🥶" if temp && temp < -10
        return "❄️" if temp && temp < 0
        return "🌤️" if temp && temp < 20
        return "☀️" if temp && temp < 30
        return "🥵" if temp && temp >= 30
        
        "🌤️"
      end
      
      def self.get_wind_emoji(wind_speed)
        return "💨" unless wind_speed.is_a?(Numeric)
        
        return "🍃" if wind_speed < 10
        return "💨" if wind_speed < 25
        return "🌪️" if wind_speed < 40
        "⚠️"
      end
      
      def self.get_precip_emoji(precip_prob)
        return "☔" unless precip_prob.is_a?(Numeric)
        
        return "🌦️" if precip_prob < 30
        return "☔" if precip_prob < 70
        "🌧️"
      end
    end
  end
end