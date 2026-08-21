module Bot
  module Commands
    class SchedulerStatus < Bot::CommandHandler
      def execute
        ensure_private_chat
        
        user = User.find_or_create_from_telegram(@message.from)
        return unless user.admin?
        
        status_info = []
        status_info << "🤖 Статус планировщика:"
        status_info << ""
        
      
        status = Bot::Helpers::Scheduler.status
        
        if status[:scheduler_running]
          status_info << "📅 Планировщик: Запущен"
          status_info << "🔧 Состояние: Активен"
          status_info << "📊 Количество задач: #{status[:jobs_count]}"
          
          if status[:daily_job_active]
            status_info << "⏰ Задача анонсов: Активна"
            if status[:next_run]
              status_info << "🕐 Следующий запуск: #{status[:next_run]}"
            else
              status_info << "🕐 Следующий запуск: Не определен"
            end
            status_info << "📝 Cron выражение: #{status[:cron_expression] || 'Неизвестно'}"
          else
            status_info << "⏰ Задача анонсов: Не найдена или неактивна"
          end
        else
          status_info << "📅 Планировщик: Не запущен"
        end
        
        status_info << "🔒 Блокировка: #{status[:lock_held] ? 'Удерживается' : 'Не удерживается'}"
        
        status_info << ""
        status_info << "⚙️ Настройки:"
        status_info << "🔔 Анонсы включены: #{APP_CONFIG.daily_announcement_enabled?}"
        status_info << "🕐 Время анонсов: #{APP_CONFIG.daily_announcement_time}"
        status_info << "🌍 Часовой пояс: #{APP_CONFIG.timezone}"
        status_info << ""
        status_info << "🆔 Процесс:"
        status_info << "🔢 PID: #{Process.pid}"
        status_info << "⏱️ Время запуска: #{APP_STARTED_AT.strftime('%d.%m.%Y %H:%M:%S')}"
        
        last_announcement_file = '/tmp/velo_utro_bot_last_announcement'
        if File.exist?(last_announcement_file)
          last_time = Time.at(File.read(last_announcement_file).to_i).in_time_zone(APP_CONFIG.timezone)
          status_info << "📢 Последний анонс: #{last_time.strftime('%d.%m.%Y %H:%M:%S')}"
        else
          status_info << "📢 Последний анонс: Не найден"
        end
        
        send_message(status_info.join("\n"))
      end
    end
  end
end
