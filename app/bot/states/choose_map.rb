module Bot
  module States
    class ChooseMap < Bot::StateHandler
      def process
        map = @message.text
        map = map == '-' ? nil : map
        
        save_event_attribute('map', map)
        transition_to_state('enter_additional_info')
        
        send_html_message(I18n.t('enter_additional_info'))
      end
    end
  end
end