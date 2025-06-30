module Bot
  module Callbacks
    class Edit_info < Bot::CallbackHandler
      def process
        event = get_event
        return unless event
        
        unless event.author_id == @user.id
          answer_callback_query(I18n.t('not_author'), show_alert: true)
          return
        end
        
        @session.edit_event_id = event.id
        @session.state = 'edit_info'
        @session.save_session
        
        send_html_message(I18n.t('edit_info'))
        
        answer_callback_query()
      end
    end
  end
end
