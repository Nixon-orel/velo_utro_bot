module Bot
  module Callbacks
    class ParticipationHandler < Bot::CallbackHandler
      protected
      
      def handle_participation(should_join)
        event = get_event
        return unless event
        
        is_participant = event.has_participant?(@user)
        
        if should_join && !is_participant
          event.participants << @user
          update_event_message(event)
          answer_callback_query(I18n.t('event_joined'))
        elsif !should_join && is_participant
          event.participants.delete(@user)
          update_event_message(event)
          answer_callback_query(I18n.t('event_unjoined'))
        else
          answer_callback_query
        end
      end
    end
  end
end