module Bot
  module Helpers
    class WeatherAdminNotifier
      def self.send_alert(level, message, data)
        return unless CONFIG['ADMIN_USER_IDS'].is_a?(Array)
        
        alert_message = format_alert_message(level, message, data)
        
        CONFIG['ADMIN_USER_IDS'].each do |admin_id|
          send_admin_message(admin_id, alert_message)
        end
      rescue => e
        puts "[WeatherAdminNotifier] Error sending admin alert: #{e.message}"
      end
      
      private
      
      def self.format_alert_message(level, message, data)
        emoji = level == :error ? "🚨" : "⚠️"
        timestamp = Time.now.strftime("%H:%M:%S")
        
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
      
      def self.send_admin_message(admin_id, message)
        return unless defined?(Rails) || defined?(Sinatra) || $bot_instance
        
        bot = $bot_instance || get_bot_instance
        return unless bot
        
        bot.api.send_message(
          chat_id: admin_id,
          text: message,
          parse_mode: 'HTML'
        )
      rescue => e
        puts "[WeatherAdminNotifier] Failed to send message to admin #{admin_id}: #{e.message}"
      end
      
      def self.get_bot_instance
        Thread.current[:bot] rescue nil
      end
    end
  end
end