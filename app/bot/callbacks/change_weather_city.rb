module Bot
  module Callbacks
    class ChangeWeatherCity < Bot::CallbackHandler
      def process
        event = get_authorized_event
        return unless event

        event_id = event.id.to_s

        prepare_event_edit(event, 'choose_weather_city')
        
        default_city = APP_CONFIG.default_weather_city
        
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
      
    end
  end
end
