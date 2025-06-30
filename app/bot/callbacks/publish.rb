module Bot
  module Callbacks
    class Publish < Bot::CallbackHandler
      def process
        event = get_event
        return unless event
        
        unless event.author_id == @user.id
          answer_callback_query(I18n.t('not_author'), show_alert: true)
          return
        end
        
        publish_to_channel(event)
        
        answer_callback_query(I18n.t('event_published'))
      end
      
      private
      
      def publish_to_channel(event)
        channel_id = CONFIG['PUBLIC_CHANNEL_ID']
        return unless channel_id
        
        event_text = Bot::Helpers::Formatter.event_info(event)
        
        buttons = [
          [
            create_button(
              I18n.t('buttons.join'),
              "join-#{event.id}"
            ),
            create_button(
              I18n.t('buttons.unjoin'),
              "unjoin-#{event.id}"
            )
          ]
        ]
        
        markup = create_keyboard(buttons)
        
        @bot.api.send_message(
          chat_id: channel_id,
          text: event_text,
          parse_mode: 'HTML',
          reply_markup: markup
        )
      rescue => e
        puts "Error publishing to channel: #{e.message}"
      end
    end
  end
end
