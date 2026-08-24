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

        status = Bot::Helpers::WeatherScheduler.status
        "#{scheduler_details(status)}\n#{outbox_details(status)}"
      rescue => e
        "⚠️ Ошибка проверки: #{e.message}"
      end

      def scheduler_details(status)
        return "❌ Отключен (WEATHER_ENABLED != true)" unless APP_CONFIG.weather_enabled?
        return '❌ Не инициализирован' unless status[:scheduler_running]

        lock_status = status[:lock_held] ? 'удерживается' : 'не удерживается'
        "✅ Активен\n📊 Задач в очереди: #{status[:jobs_count]}\n🔒 Блокировка: #{lock_status}"
      end

      def outbox_details(status)
        counts = status[:outbox_counts]
        waiting_count = counts.fetch(:pending, 0) + counts.fetch(:processing, 0)
        lines = [
          "📨 Ожидают доставки: #{waiting_count}",
          "⚠️ Актуальных ошибок доставки: #{status[:current_failed_count]}",
          "🗄 Исторических ошибок доставки: #{status[:historical_failed_count]}"
        ]
        if status[:current_failed_count].positive?
          lines << "🎯 События с ошибками: #{status[:failed_event_ids].join(', ')}"
          lines << "🕐 Самая ранняя ошибка: #{format_status_time(status[:oldest_failed_at])}"
        end
        lines.join("\n")
      end

      def format_status_time(time)
        time.in_time_zone(APP_CONFIG.timezone).strftime('%d.%m.%Y %H:%M')
      end
      
      def check_api_status
        return '❌ API ключ не установлен' if APP_CONFIG.weather_api_key.to_s.empty?

        default_coords = APP_CONFIG.default_weather_coordinates
        default_city = APP_CONFIG.default_weather_city
        return '❌ Координаты по умолчанию не установлены' if default_coords.blank?

        require_relative '../../services/weather_service'

        started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        weather_data = WeatherService.fetch_weather_for_event(
          default_coords.gsub(/\s+/, ''),
          AppClock.today,
          AppClock.now.strftime('%H:%M')
        )
        response_time = elapsed_milliseconds_since(started_at)

        return '⚠️ API отвечает, но данные отсутствуют' unless weather_data

        temp = weather_data['temp_c']
        condition = weather_data['condition']
        "✅ Доступен\n🏙️ #{default_city}: #{condition}, #{temp}°C\n⏱️ Время ответа: #{response_time}мс"
      rescue => e
        "❌ Недоступен: #{e.message}"
      end

      def elapsed_milliseconds_since(started_at)
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
        (elapsed * 1000).round
      end
    end
  end
end
