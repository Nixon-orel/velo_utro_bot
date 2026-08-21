module Bot
  module Helpers
    class WeatherAdminNotifier
      def initialize(bot)
        @gateway = Notifications::TelegramGateway.new(bot)
      end

      def send_alert(level, message, data)
        return if APP_CONFIG.admin_ids.empty?
        
        alert_message = format_alert_message(level, message, data)
        
        APP_CONFIG.admin_ids.each do |admin_id|
          send_admin_message(admin_id, alert_message)
        end
      rescue => e
        AppLogger.error('Bot::Helpers::WeatherAdminNotifier', 'Failed to send admin alert', exception: e)
      end
      
      private
      
      def format_alert_message(level, message, data)
        emoji = level == :error ? "🚨" : "⚠️"
        timestamp = AppClock.now.strftime("%H:%M:%S")
        
        alert_text = "#{emoji} <b>Weather System Alert</b>\n"
        alert_text += "🕐 #{timestamp}\n"
        alert_text += "📋 #{message}\n"
        
        if data && !data.empty?
          alert_text += "\n📊 <b>Details:</b>\n"
          
          if data[:coordinates]
            alert_text += "📍 Coordinates: #{data[:coordinates]}\n"
          end
          
          if data[:event_id]
            alert_text += "🎯 Event ID: #{data[:event_id]}\n"
          end
          
          if data[:status]
            alert_text += "📡 HTTP Status: #{data[:status]}\n"
          end
          
          if data[:retry_count]
            alert_text += "🔄 Retry Count: #{data[:retry_count]}\n"
          end
          
          if data[:error]
            alert_text += "❌ Error Type: #{data[:error]}\n"
          end
          
          if data[:fallback_age_hours]
            alert_text += "⏰ Fallback Age: #{data[:fallback_age_hours]}h\n"
          end
        end
        
        alert_text
      end
      
      def send_admin_message(admin_id, message)
        @gateway.send_message(
          chat_id: admin_id,
          text: message,
          parse_mode: 'HTML'
        )
      rescue => e
        AppLogger.error(
          'Bot::Helpers::WeatherAdminNotifier',
          'Failed to notify admin',
          admin_id: admin_id,
          exception: e
        )
      end
      
    end
  end
end
