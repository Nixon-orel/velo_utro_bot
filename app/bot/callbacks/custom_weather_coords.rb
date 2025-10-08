module Bot
  module Callbacks
    class CustomWeatherCoords < Bot::CallbackHandler
      def process
        event_id = get_event_id
        event = get_event
        return unless event

        @session.edit_event_id = event_id
        transition_to_state('enter_weather_latitude')
        
        send_message(I18n.t('enter_weather_latitude'))
        answer_callback_query("Введите координаты места")
      end
      
      private
      
      def transition_to_state(state)
        @session.state = state
        @session.save_session
      end
    end
  end
end