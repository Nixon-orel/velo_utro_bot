module Bot
  module Callbacks
    class ParticipationHandler < Bot::CallbackHandler
      protected
      
      def handle_participation(should_join)
        event = get_event
        return unless event
        
        result = Events::ChangeParticipation.call(event: event, actor: @user, join: should_join)
        if result.failure?
          AppLogger.error(
            'Bot::Callbacks::ParticipationHandler',
            'Failed to change participation',
            event_id: event.id,
            user_id: @user&.id,
            error_code: result.error_code,
            exception: result.error
          )
          answer_callback_query(I18n.t('invalid_input'), show_alert: true)
          return
        end

        if result.metadata[:changed]
          update_event_message(event)
          message_key = should_join ? 'event_joined' : 'event_unjoined'
          answer_callback_query(I18n.t(message_key))
        else
          answer_callback_query
        end
      end
    end
  end
end
