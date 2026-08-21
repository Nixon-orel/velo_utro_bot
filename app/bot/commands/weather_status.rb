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
        
        unless APP_CONFIG.weather_enabled?
          return "❌ Отключен (WEATHER_ENABLED != true)"
        end
        
        begin
          status = Bot::Helpers::WeatherScheduler.status

          unless status[:scheduler_running]
            return "❌ Не инициализирован"
          end

          lock_status = status[:lock_held] ? 'удерживается' : 'не удерживается'
          "✅ Активен\n📊 Задач в очереди: #{status[:jobs_count]}\n🔒 Блокировка: #{lock_status}"
        rescue => e
          return "⚠️ Ошибка проверки: #{e.message}"
        end
      end
      
      def check_api_status
        if APP_CONFIG.weather_api_key.to_s.empty?
          return "❌ API ключ не установлен"
        end
        
        default_coords = APP_CONFIG.default_weather_coordinates
        default_city = APP_CONFIG.default_weather_city
        
        if default_coords.nil? || default_coords.empty?
          return "❌ Координаты по умолчанию не установлены"
        end
        
        begin
          require_relative '../../services/weather_service'
          
          started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          coords_clean = default_coords.gsub(/\s+/, '')
          weather_data = WeatherService.fetch_weather_for_event(coords_clean, AppClock.today, AppClock.now.strftime("%H:%M"))
          elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
          response_time = (elapsed * 1000).round
          
          if weather_data
            temp = weather_data['temp_c']
            condition = weather_data['condition']
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
