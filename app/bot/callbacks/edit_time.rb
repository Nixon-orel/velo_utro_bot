module Bot
  module Callbacks
    class EditTime < Bot::CallbackHandler
      def process
        event = get_authorized_event
        return unless event

        prepare_event_edit(event, 'edit_time')
        
        message_text = Mustache.render(I18n.t('edit_time'), { event: event })
        send_html_message(message_text)
        
        answer_callback_query()
      end
    end
  end
end
