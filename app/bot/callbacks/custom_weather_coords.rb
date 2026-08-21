module Bot
  module Callbacks
    class CustomWeatherCoords < Bot::CallbackHandler
      def process
        event = get_authorized_event
        return unless event

        prepare_event_edit(event, 'enter_weather_latitude')
        
        send_message(I18n.t('enter_weather_latitude'))
        answer_callback_query("Введите координаты места")
      end
      
    end
  end
end
