module Bot
  module States
    class EditHandler < Bot::StateHandler
      protected
      
      def edit_event_field(field, value, notification_key, saved_key, validation_pattern = nil)
        if validation_pattern && !validate_input(value, validation_pattern)
          send_message(I18n.t('invalid_input'))
          return
        end
        
        event = get_edit_event
        return unless event
        
        processed_value = process_value(value)
        old_value = event.send(field)
        
        event.update(field => processed_value)
        
        if should_notify?(processed_value, old_value)
          notify_about_change(event, notification_key, processed_value)
        end
        
        reset_edit_state
        send_confirmation(saved_key)
      end
      
      def process_value(value)
        value == '-' ? nil : value
      end
      
      def should_notify?(new_value, old_value)
        new_value && new_value != old_value
      end
      
      private
      
      def get_edit_event
        event_id = @session.edit_event_id
        event = Event.find_by(id: event_id)
        
        unless event
          send_message(I18n.t('invalid_input'))
          reset_edit_state
          return nil
        end
        
        event
      end
      
      def notify_about_change(event, notification_key, new_value)
        notifier = Bot::Helpers::Notifier.new(@bot)
        param_key = notification_key.split('_')[0]
        params = { "new_#{param_key}".to_sym => new_value }
        
        notifier.notify_participants(event, "#{notification_key}_notification", params)
        notifier.notify_channel_about_change(event, "#{notification_key}_channel_notification", params)
      end
      
      def reset_edit_state
        @session.state = nil
        @session.edit_event_id = nil
        @session.save_session
      end
      
      def send_confirmation(saved_key)
        send_message(I18n.t(saved_key))
        send_message(I18n.t('event_updated'))
      end
    end
  end
end