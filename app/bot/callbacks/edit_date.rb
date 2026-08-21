module Bot
  module Callbacks
    class EditDate < Bot::CallbackHandler
      def process
        event = get_authorized_event
        return unless event

        prepare_event_edit(event, 'edit_date', calendar_type: 'edit')
        
        message_text = Mustache.render(I18n.t('edit_date'), { event: event })
        send_html_message(message_text)
        
        calendar = Bot::Helpers::Calendar.new
        calendar.send_to(@bot, @message.message.chat.id)
        
        answer_callback_query()
      end
    end
  end
end
