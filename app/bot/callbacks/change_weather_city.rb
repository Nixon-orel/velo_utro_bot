module Bot
  module Callbacks
    class ChangeWeatherCity < Bot::CallbackHandler
      def process
        event_id = get_event_id
        event = get_event
        return unless event

        @session.edit_event_id = event_id
        transition_to_state('choose_weather_city')
        
        default_city = ENV['DEFAULT_WEATHER_CITY_NAME'] || 'Орёл'
        
        buttons = [
          [
            create_button(
              I18n.t('use_default_weather_city', city: default_city),
              "default_weather_city-#{event_id}"
            )
          ],
          [
            create_button(
              I18n.t('enter_custom_coordinates'),
              "custom_weather_coords-#{event_id}"
            )
          ]
        ]
        
        markup = create_keyboard(buttons)
        send_message(I18n.t('choose_weather_city'), { reply_markup: markup })
        answer_callback_query("Выберите источник погодных данных")
      end
      
      private
      
      def transition_to_state(state)
        @session.state = state
        @session.save_session
      end
    end
  end
end