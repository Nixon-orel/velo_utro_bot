module Bot
  module States
    class ChooseTrack < Bot::StateHandler
      def process
        track = @message.text
        track = track == '-' ? nil : track
        
        save_event_attribute('track', track)
        transition_to_state('choose_map')
        
        send_html_message(I18n.t('choose_map'))
      end
    end
  end
end