module Bot
  module Callbacks
    class Edit_date < Bot::CallbackHandler
      def process
        event = get_event
        return unless event
        
        unless event.author_id == @user.id
          answer_callback_query(I18n.t('not_author'), show_alert: true)
          return
        end
        
        @session.edit_event_id = event.id
        @session.state = 'edit_date'
        @session.calendar_type = 'edit'
        @session.save_session
        
        message_text = Mustache.render(I18n.t('edit_date'), { event: event })
        send_html_message(message_text)
        
        calendar = Bot::Helpers::Calendar.new
        calendar.send_to(@bot, @message.message.chat.id)
        
        answer_callback_query()
      end
    end
  end
end