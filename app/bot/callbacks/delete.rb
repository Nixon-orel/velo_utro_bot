module Bot
  module Callbacks
    class Delete < Bot::CallbackHandler
      def process
        event = get_event
        return unless event
        
        result = Events::DeleteEvent.call(event: event, actor: @user)

        if result.error_code == :forbidden
          answer_callback_query(I18n.t('not_author'), show_alert: true)
          return
        end

        if result.failure?
          AppLogger.error(
            'Bot::Callbacks::Delete',
            'Failed to delete event',
            event_id: event.id,
            error_code: result.error_code,
            exception: result.error
          )
          answer_callback_query(I18n.t('invalid_input'), show_alert: true)
          return
        end

        Bot::Helpers::WeatherScheduler.cancel_for(event.id)
        notify_channel_about_deletion(event)
        result.metadata[:participants].each do |participant|
          send_deletion_notification(participant, event)
        end

        delete_message
        answer_callback_query(I18n.t('event_deleted'))
      end
      
      private
      
      def send_deletion_notification(participant, event)
        vars = {
          event: {
            event_type: event.event_type,
            formatted_date: event.formatted_date,
            formatted_time: event.formatted_time
          }
        }
        
        template = I18n.t('event_deleted_notification')
        notification = Mustache.render(template, vars)
        
        begin
          @bot.api.send_message(
            chat_id: participant.telegram_id,
            text: notification,
            parse_mode: 'HTML'
          )
        rescue => e
          AppLogger.error(
            'Bot::Callbacks::Delete',
            'Failed to notify participant',
            participant_id: participant.id,
            event_id: event.id,
            exception: e
          )
        end
      end
      
      def notify_channel_about_deletion(event)
        channel_id = APP_CONFIG.public_channel_id
        return unless channel_id
        return unless event.published
        
        event_datetime = event.starts_at
        return unless event_datetime
        return if event_datetime < AppClock.now
        
        notifier = Bot::Helpers::Notifier.new(@bot)
        notifier.notify_channel_about_change(event, 'event_deleted_channel_notification')
        
      rescue => e
        AppLogger.error(
          'Bot::Callbacks::Delete',
          'Failed to notify channel about event deletion',
          event_id: event.id,
          exception: e
        )
      end
    end
  end
end
