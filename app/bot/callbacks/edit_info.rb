module Bot
  module Callbacks
    class EditInfo < Bot::CallbackHandler
      def process
        event = get_authorized_event
        return unless event

        prepare_event_edit(event, 'edit_info')
        
        send_html_message(I18n.t('edit_info'))
        
        answer_callback_query()
      end
    end
  end
end
