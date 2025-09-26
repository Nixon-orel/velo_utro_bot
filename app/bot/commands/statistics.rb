module Bot
  module Commands
    class Statistics < Bot::CommandHandler
      def execute
        if admin_user?
          send_statistics_report
        else
          send_message(I18n.t('admin_only'))
        end
      end
      
      private
      
      def send_statistics_report
        statistics = Bot::Helpers::Statistics.new(@bot)
        data = statistics.monthly_report
        message = statistics.format_monthly_report(data)
        
        send_message(message, parse_mode: 'HTML')
      rescue => e
        send_message("❌ Ошибка при генерации статистики: #{e.message}")
      end
      
      def admin_user?
        admin_ids = ENV['ADMIN_IDS'].to_s.split(',').map(&:to_i)
        admin_ids.include?(@message.from.id)
      end
    end
  end
end