module Bot
  module Callbacks
    class EditTrack < Bot::CallbackHandler
      def process
        event = get_authorized_route_event
        return unless event

        prepare_event_edit(event, 'edit_track')
        
        message_text = Mustache.render(I18n.t('edit_track'), { event: event })
        send_html_message(message_text)
        
        answer_callback_query()
      end
    end
  end
end
