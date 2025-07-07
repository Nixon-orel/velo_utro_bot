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
        
        participants = event.participants.to_a
        
        notify_channel_about_deletion(event)
        
        if participants.any?
          participants.each do |participant|
            send_deletion_notification(participant, event)
          end
        end
        
        event.destroy
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
          puts "Failed to notify participant #{participant.telegram_id}: #{e.message}"
        end
      end
      
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