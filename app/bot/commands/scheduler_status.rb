module Bot
  module Commands
    class SchedulerStatus < Bot::CommandHandler
      def execute
        return unless ensure_private_chat
        
        user = User.find_or_create_from_telegram(@message.from)
        unless user.admin?
          send_message(I18n.t('admin_only'))
          return
        end
        
        status_info = []
        status_info << "🤖 Статус планировщика:"
        status_info << ""
        
      
        status = Bot::Helpers::Scheduler.status
        
        if status[:scheduler_running]
          status_info << "📅 Планировщик: Запущен"
          status_info << "🔧 Состояние: Активен"
          status_info << "📊 Количество задач: #{status[:jobs_count]}"
          daily_state = status[:daily_job_active] ? 'Активна' : 'Неактивна'
          status_info << "🔔 Ежедневные анонсы: #{daily_state}"
          status_info << "🕐 Следующий анонс (UTC): #{status[:next_run]}" if status[:next_run]
          monthly_state = status[:monthly_job_active] ? 'Активна' : 'Неактивна'
          status_info << "📈 Задача месячной статистики: #{monthly_state}"
        else
          status_info << "📅 Планировщик: Не запущен"
        end
        
        status_info << "🔒 Блокировка: #{status[:lock_held] ? 'Удерживается' : 'Не удерживается'}"
        
        status_info << ""
        status_info << "⚙️ Настройки:"
        status_info << "🔔 Ежедневные анонсы: #{APP_CONFIG.daily_announcement_enabled? ? 'Включены' : 'Выключены'}"
        status_info << "🕐 Время анонсов (UTC): #{APP_CONFIG.daily_announcement_time}"
        last_announcement = status[:last_announcement_at]
        last_announcement_text = if last_announcement
          last_announcement.in_time_zone(APP_CONFIG.timezone).strftime('%d.%m.%Y %H:%M:%S')
        else
          'Не отправлялся'
        end
        status_info << "📢 Последний анонс: #{last_announcement_text}"
        status_info << "📆 День месячной статистики: #{APP_CONFIG.monthly_stats_day || 'Не задан'}"
        status_info << "🌍 Часовой пояс: #{APP_CONFIG.timezone}"
        status_info << ""
        status_info << "🆔 Процесс:"
        status_info << "🔢 PID: #{Process.pid}"
        status_info << "⏱️ Время запуска: #{APP_STARTED_AT.strftime('%d.%m.%Y %H:%M:%S')}"
        
        send_message(status_info.join("\n"))
      end
    end
  end
end
