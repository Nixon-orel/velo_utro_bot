module Bot
  module Callbacks
    class EditTrack < Bot::CallbackHandler
      def process
        event = get_event
        return unless event
        
        unless event.author_id == @user.id
          answer_callback_query(I18n.t('not_author'), show_alert: true)
          return
        end
        
        @session.edit_event_id = event.id
        @session.state = 'edit_track'
        @session.save_session
        
        message_text = Mustache.render(I18n.t('edit_track'), { event: event })
        send_html_message(message_text)
        
        answer_callback_query()
      end
    end
  end
end
