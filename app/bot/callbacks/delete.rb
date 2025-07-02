module Bot
  module Callbacks
    class Delete < Bot::CallbackHandler
      def process
        event = get_event
        return unless event
        
        unless event.author_id == @user.id
          answer_callback_query(I18n.t('not_author'), show_alert: true)
          return
        end
        
        if event.participants.any?
          notifier = Bot::Helpers::Notifier.new(@bot)
          notifier.notify_participants(event, 'event_deleted_notification')
        end
        
        notify_channel_about_deletion(event)
        event.destroy
        delete_message
        answer_callback_query(I18n.t('event_deleted'))
      end
      
      private
      
      def notify_channel_about_deletion(event)
        channel_id = CONFIG['PUBLIC_CHANNEL_ID']
        return unless channel_id
        event_datetime = DateTime.parse("#{event.date} #{event.time}")
        return if event_datetime < DateTime.now
        
        notifier = Bot::Helpers::Notifier.new(@bot)
        notifier.notify_channel_about_change(event, 'event_deleted_channel_notification')
        return
        
      rescue => e
        puts "Error notifying channel about event deletion: #{e.message}"
      end
    end
  end
end