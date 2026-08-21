module Bot
  module Commands
    class Announcement < Bot::CommandHandler
      def execute
        return unless ensure_private_chat
        unless @user.admin?
          send_message('У вас нет прав для выполнения этой команды')
          return
        end
        
        publish_events_to_channel
      end
      
      private
      
      def publish_events_to_channel
        begin
          events = Event.today
          
          @bot.api.send_message(
            chat_id: APP_CONFIG.public_channel_id,
            text: I18n.t('events_for_today'),
            parse_mode: 'HTML'
          )
          
          if events.empty?
            @bot.api.send_message(
              chat_id: APP_CONFIG.public_channel_id,
              text: I18n.t('no_events_today2'),
              parse_mode: 'HTML'
            )
            
            send_message(I18n.t('publish_no_events'))
          else
            events.each_with_index do |event, index|
              message = Bot::Helpers::Formatter.event_info(event)
              
              if event.weather_data.present? && APP_CONFIG.weather_enabled?
                require_relative '../../services/weather_recommendations'
                recommendations = WeatherRecommendations.generate(event.weather_data, event.time)
                if recommendations.any?
                  formatted_recommendations = recommendations.map { |recommendation| "• #{recommendation}" }.join("\n")
                  message += "\n\n💡 <b>Рекомендации:</b>\n#{formatted_recommendations}"
                end
              end
              
              buttons = []
              
              if index == events.length - 1
                buttons << [
                  create_url_button(
                    I18n.t('buttons.more'),
                    "https://t.me/#{APP_CONFIG.bot_username}"
                  )
                ]
              end
              
              markup = buttons.empty? ? nil : create_keyboard(buttons)
              
              @bot.api.send_message(
                chat_id: APP_CONFIG.public_channel_id,
                text: message,
                parse_mode: 'HTML',
                reply_markup: markup
              )
            end
            
            send_message(I18n.t('publish_success', count: events.length))
          end
        rescue => e
          send_message("#{I18n.t('publish_error')} #{e.message}")
        end
      end
    end
  end
end
