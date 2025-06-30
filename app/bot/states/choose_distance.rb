module Bot
  module States
    class Choose_distance < Bot::StateHandler
      def process
        distance = @message.text
        
        save_event_attribute('distance', distance)
        transition_to_state('choose_pace')
        
        send_message(I18n.t('choose_pace'))
      end
    end
  end
end