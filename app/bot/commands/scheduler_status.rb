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
          
          if status[:job_active]
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
        
        status_info << "🔒 Файл блокировки: #{status[:lock_file_exists] ? 'Существует' : 'Отсутствует'}"
        
        status_info << ""
        status_info << "⚙️ Настройки:"
        status_info << "🔔 Анонсы включены: #{CONFIG['DAILY_ANNOUNCEMENT_ENABLED']}"
        status_info << "🕐 Время анонсов: #{CONFIG['DAILY_ANNOUNCEMENT_TIME']}"
        status_info << "🌍 Часовой пояс: #{CONFIG['TIMEZONE']}"
        status_info << ""
        status_info << "🆔 Процесс:"
        status_info << "🔢 PID: #{Process.pid}"
        status_info << "⏱️ Время запуска: #{Time.at($PROGRAM_START_TIME || Time.now).strftime('%d.%m.%Y %H:%M:%S')}"
        
        last_announcement_file = '/tmp/velo_utro_bot_last_announcement'
        if File.exist?(last_announcement_file)
          last_time = Time.at(File.read(last_announcement_file).to_i)
          status_info << "📢 Последний анонс: #{last_time.strftime('%d.%m.%Y %H:%M:%S')}"
        else
          status_info << "📢 Последний анонс: Не найден"
        end
        
        send_message(status_info.join("\n"))
      end
    end
  end
end