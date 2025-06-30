module Bot
  module States
    class Choose_pace < Bot::StateHandler
      def process
        pace = @message.text
        
        save_event_attribute('pace', pace)
        transition_to_state('choose_track')
        
        send_html_message(I18n.t('choose_track'))
      end
    end
  end
end