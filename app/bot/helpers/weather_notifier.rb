module Bot
  module Helpers
    class WeatherNotifier
      def initialize(bot)
        @gateway = Notifications::TelegramGateway.new(bot)
      end

      def handle_3d_weather_update(event, old_weather, new_weather)
        return unless event && new_weather

        old_weather = Weather::Forecast.normalize(old_weather)
        new_weather = Weather::Forecast.normalize(new_weather)
        
        if old_weather && old_weather['is_fallback']
          send_accurate_weather_update(event, old_weather, new_weather)
        elsif weather_changed_critically?(old_weather, new_weather)
          send_critical_weather_alerts(event, old_weather, new_weather)
        else
          update_event_message_silently(event)
        end
      end
      
      def handle_24h_weather_update(event, old_weather, new_weather)
        return unless event && new_weather

        old_weather = Weather::Forecast.normalize(old_weather)
        new_weather = Weather::Forecast.normalize(new_weather)
        
        if weather_changed_critically?(old_weather, new_weather)
          send_critical_weather_alerts(event, old_weather, new_weather)
        else
          update_event_message_silently(event)
        end
      end
      
      def handle_2h_weather_update(event, weather_data)
        return unless event && weather_data

        weather_data = Weather::Forecast.normalize(weather_data)
        
        send_channel_weather_forecast(event, weather_data)
      end
      
      private
      
      def weather_changed_critically?(old_weather, new_weather)
        return false if old_weather.empty?
        
        temp_change = (new_weather['temp_c'].to_f - old_weather['temp_c'].to_f).abs
        
        old_precip = old_weather['precip_prob'].to_i > 50
        new_precip = new_weather['precip_prob'].to_i > 50
        precip_change = old_precip != new_precip
        
        wind_change = (new_weather['wind_kph'].to_f - old_weather['wind_kph'].to_f).abs > 15
        
        alerts_appeared = !new_weather['alerts'].to_a.empty? && old_weather['alerts'].to_a.empty?
        
        temp_change > 5 || precip_change || wind_change || alerts_appeared
      end
      
      def send_critical_weather_alerts(event, old_weather, new_weather)
        require_relative '../../services/weather_recommendations'
        
        message = format_critical_change_message(event, old_weather, new_weather)
        
        all_users = ([event.author] + event.participants).uniq
        all_users.each do |user|
          send_message_to_user(user, message)
        end
        
        event.weather_alerts_sent ||= {}
        event.weather_alerts_sent['24h_critical'] = AppClock.now.to_s
        event.save
        
        AppLogger.info('Bot::Helpers::WeatherNotifier', 'Critical weather alerts sent', event_id: event.id)
      end
      
      def send_accurate_weather_update(event, old_weather, new_weather)
        require_relative '../../services/weather_recommendations'
        
        message = format_accurate_weather_message(event, old_weather, new_weather)
        
        all_users = ([event.author] + event.participants).uniq
        all_users.each do |user|
          send_message_to_user(user, message)
        end
        
        # Обновляем сообщение в канале с точными данными
        update_event_message_silently(event)
        
        event.weather_alerts_sent ||= {}
        event.weather_alerts_sent['3d_accurate'] = AppClock.now.to_s
        event.save
        
        AppLogger.info('Bot::Helpers::WeatherNotifier', 'Accurate weather update sent', event_id: event.id)
      end
      
      def update_event_message_silently(event)
        return unless event.channel_message_id && APP_CONFIG.public_channel_id
        
        begin
          updated_message = Bot::Helpers::Formatter.event_info(event)
          
          @gateway.edit_message_text(
            chat_id: APP_CONFIG.public_channel_id,
            message_id: event.channel_message_id,
            text: updated_message,
            parse_mode: 'HTML'
          )
          
          AppLogger.info('Bot::Helpers::WeatherNotifier', 'Event message updated', event_id: event.id)
        rescue => e
          AppLogger.error(
            'Bot::Helpers::WeatherNotifier',
            'Failed to update event message',
            event_id: event.id,
            exception: e
          )
        end
      end
      
      def send_channel_weather_forecast(event, weather_data)
        require_relative '../../services/weather_recommendations'
        return unless event.published?
        
        channel_id = APP_CONFIG.public_channel_id
        return unless channel_id
        
        recommendations = WeatherRecommendations.generate(weather_data, event.time)
        weather_info = format_weather_info(weather_data, recommendations)
        
        message = I18n.t('weather.channel_forecast_message',
          event_type: event.event_type,
          date: event.formatted_date,
          time: event.formatted_time,
          location: event.location,
          weather_info: weather_info
        )
        
        begin
          @gateway.send_message(
            chat_id: channel_id,
            text: message,
            parse_mode: 'HTML'
          )
          
          event.weather_alerts_sent ||= {}
          event.weather_alerts_sent['2h_channel'] = AppClock.now.to_s
          event.save
          
          AppLogger.info('Bot::Helpers::WeatherNotifier', 'Channel forecast sent', event_id: event.id)
        rescue => e
          AppLogger.error(
            'Bot::Helpers::WeatherNotifier',
            'Failed to send channel forecast',
            event_id: event.id,
            exception: e
          )
        end
      end
      
      def format_critical_change_message(event, old_weather, new_weather)
        require_relative '../../services/weather_recommendations'
        
        old_condition = old_weather['condition'] || 'Неизвестно'
        old_temp = old_weather['temp_c'] || 'N/A'
        
        new_condition = new_weather['condition']
        new_temp = new_weather['temp_c']
        new_wind = new_weather['wind_kph']
        new_precip = new_weather['precip_prob']
        
        recommendations = WeatherRecommendations.generate(new_weather, event.time)
        
        message = I18n.t('weather.critical_change_header',
          event_type: event.event_type,
          date: event.formatted_date,
          time: event.formatted_time
        )
        
        message += "\n\n#{I18n.t('weather.was')}: #{old_condition}, #{old_temp}°C"
        message += "\n#{I18n.t('weather.became')}: #{new_condition}, #{new_temp}°C"
        
        if new_wind && new_wind > 10
          message += ", ветер #{new_wind} км/ч"
        end
        
        if new_precip && new_precip > 30
          message += ", осадки #{new_precip}%"
        end
        
        if recommendations.any?
          message += "\n\n#{I18n.t('weather.recommendations')}:"
          recommendations.first(4).each { |rec| message += "\n• #{rec}" }
        end
        
        message
      end
      
      def format_accurate_weather_message(event, old_weather, new_weather)
        require_relative '../../services/weather_recommendations'
        
        recommendations = WeatherRecommendations.generate(new_weather, event.time)
        
        message = I18n.t('weather.accurate_update_header',
          event_type: event.event_type,
          date: event.formatted_date,
          time: event.formatted_time
        )
        
        fallback_date = old_weather['fallback_from'] || 'неизвестной даты'
        message += "\n\n📅 Ранее: приблизительный прогноз (данные за #{fallback_date})"
        
        new_condition = new_weather['condition']
        new_temp = new_weather['temp_c']
        new_wind = new_weather['wind_kph']
        new_precip = new_weather['precip_prob']
        
        message += "\n🎯 Сейчас: точный прогноз - #{new_condition}, #{new_temp}°C"
        
        if new_wind && new_wind > 10
          message += ", ветер #{new_wind} км/ч"
        end
        
        if new_precip && new_precip > 30
          message += ", осадки #{new_precip}%"
        end
        
        if recommendations.any?
          message += "\n\n⚡ Рекомендации:"
          recommendations.first(4).each { |rec| message += "\n• #{rec}" }
        end
        
        message
      end
      
      def format_weather_info(weather_data, recommendations)
        temp = weather_data['temp_c']
        feels_like = weather_data['feelslike_c']
        condition = weather_data['condition']
        wind_speed = weather_data['wind_kph']
        precip_prob = weather_data['precip_prob']
        
        weather_text = "🌤️ #{condition}, #{temp}°C"
        weather_text += " (ощущ. #{feels_like}°C)" if feels_like && feels_like != temp
        weather_text += "\n💨 Ветер: #{wind_speed} км/ч" if wind_speed
        weather_text += "\n☔ Вероятность осадков: #{precip_prob}%" if precip_prob
        
        if recommendations.any?
          weather_text += "\n\n⚡ Рекомендации:"
          recommendations.first(3).each { |rec| weather_text += "\n• #{rec}" }
        end
        
        weather_text
      end
      
      def send_message_to_user(user, message)
        begin
          @gateway.send_message(
            chat_id: user.telegram_id,
            text: message,
            parse_mode: 'HTML'
          )
          AppLogger.debug('Bot::Helpers::WeatherNotifier', 'Weather message sent', user_id: user.id)
        rescue => e
          AppLogger.error(
            'Bot::Helpers::WeatherNotifier',
            'Failed to notify user',
            user_id: user.id,
            exception: e
          )
        end
      end
      
    end
  end
end
