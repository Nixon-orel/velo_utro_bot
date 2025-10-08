module Bot
  module Commands
    class WeatherStatus < Bot::CommandHandler
      def execute
        return unless ensure_private_chat
        unless @user.admin?
          send_message(I18n.t('admin_only'))
          return
        end
        
        check_weather_status
      end
      
      private
      
      def check_weather_status
        status_message = "🌤️ <b>Статус погодной системы</b>\n\n"
        
        scheduler_status = check_scheduler_status
        api_status = check_api_status
        
        status_message += "📋 <b>Планировщик:</b>\n#{scheduler_status}\n\n"
        status_message += "🌐 <b>API погоды:</b>\n#{api_status}"
        
        send_html_message(status_message)
      end
      
      def check_scheduler_status
        require_relative '../helpers/weather_scheduler'
        
        if ENV['WEATHER_ENABLED'] != 'true'
          return "❌ Отключен (WEATHER_ENABLED != true)"
        end
        
        begin
          scheduler = Bot::Helpers::WeatherScheduler.class_variable_get(:@@scheduler)
          
          if scheduler.nil?
            return "❌ Не инициализирован"
          end
          
          if scheduler.up?
            running_jobs = scheduler.jobs.size
            return "✅ Активен\n📊 Задач в очереди: #{running_jobs}"
          else
            return "❌ Остановлен"
          end
        rescue => e
          return "⚠️ Ошибка проверки: #{e.message}"
        end
      end
      
      def check_api_status
        if ENV['WEATHER_API_KEY'].nil? || ENV['WEATHER_API_KEY'].empty?
          return "❌ API ключ не установлен"
        end
        
        default_coords = ENV['DEFAULT_WEATHER_COORDINATES']
        default_city = ENV['DEFAULT_WEATHER_CITY_NAME'] || 'неизвестный город'
        
        if default_coords.nil? || default_coords.empty?
          return "❌ Координаты по умолчанию не установлены"
        end
        
        begin
          require_relative '../../services/weather_service'
          
          start_time = Time.now
          coords_clean = default_coords.gsub(/\s+/, '')
          weather_data = WeatherService.fetch_weather_for_event(coords_clean, Date.today, Time.now.strftime("%H:%M"))
          response_time = ((Time.now - start_time) * 1000).round
          
          if weather_data
            temp = weather_data[:temp_c]
            condition = weather_data[:condition]
            return "✅ Доступен\n🏙️ #{default_city}: #{condition}, #{temp}°C\n⏱️ Время ответа: #{response_time}мс"
          else
            return "⚠️ API отвечает, но данные отсутствуют"
          end
        rescue => e
          return "❌ Недоступен: #{e.message}"
        end
      end
    end
  end
end