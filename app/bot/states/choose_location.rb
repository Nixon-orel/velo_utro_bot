module Bot
  module States
    class ChooseLocation < Bot::StateHandler
      def process
        location = @message.text
        
        save_event_attribute('location', location)
        
        event_type = @session.new_event['type']
        
        if static_event?(event_type)
          transition_to_state('enter_additional_info')
          send_html_message(I18n.t('enter_additional_info'))
        else
          transition_to_state('choose_distance')
          send_message(I18n.t('choose_distance'))
        end
      end
    end
  end
end