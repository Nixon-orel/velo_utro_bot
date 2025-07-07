module Bot
  module Commands
    class SchedulerStatus < Bot::CommandHandler
      def execute
        ensure_private_chat
        
        user = User.find_or_create_from_telegram(@message.from)
        return unless user.admin?
        
        status_info = []
        status_info << "🤖 <b>Статус планировщика:</b>"
        status_info << ""
        
      
        status = Bot::Helpers::Scheduler.status
        
        if status[:scheduler_running]
          status_info << "📅 Планировщик: <b>Запущен</b>"
          status_info << "🔧 Состояние: <b>Активен</b>"
          status_info << "📊 Количество задач: #{status[:jobs_count]}"
          
          if status[:job_active] && status[:next_run]
            status_info << "⏰ Задача анонсов: <b>Активна</b>"
            status_info << "🕐 Следующий запуск: #{status[:next_run]}"
            status_info << "📝 Cron выражение: #{status[:cron_expression] || 'Неизвестно'}"
          else
            status_info << "⏰ Задача анонсов: <b>Не найдена или неактивна</b>"
          end
        else
          status_info << "📅 Планировщик: <b>Не запущен</b>"
        end
        
        status_info << "🔒 Файл блокировки: #{status[:lock_file_exists] ? 'Существует' : 'Отсутствует'}"
        
        status_info << ""
        status_info << "⚙️ <b>Настройки:</b>"
        status_info << "🔔 Анонсы включены: #{CONFIG['DAILY_ANNOUNCEMENT_ENABLED']}"
        status_info << "🕐 Время анонсов: #{CONFIG['DAILY_ANNOUNCEMENT_TIME']}"
        status_info << "🌍 Часовой пояс: #{CONFIG['TIMEZONE']}"
        status_info << ""
        status_info << "🆔 <b>Процесс:</b>"
        status_info << "🔢 PID: #{Process.pid}"
        status_info << "⏱️ Время запуска: #{Time.at($PROGRAM_START_TIME || Time.now).strftime('%d.%m.%Y %H:%M:%S')}"
        
        send_message(status_info.join("\n"))
      end
    end
  end
end