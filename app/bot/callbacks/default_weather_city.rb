module Bot
  module Callbacks
    class DefaultWeatherCity < Bot::CallbackHandler
      def process
        event_id = get_event_id
        event = get_event
        return unless event

        default_coordinates = ENV['DEFAULT_WEATHER_COORDINATES'] || '52.9651,36.0785'
        default_city = ENV['DEFAULT_WEATHER_CITY_NAME'] || 'Орёл'
        
        update_event_weather(event, default_coordinates, default_city)
        
        transition_to_state(nil)
        answer_callback_query("Прогноз обновлен")
        
        message = Bot::Helpers::Formatter.event_info(event)
        buttons = [
          [
            create_button(
              I18n.t('buttons.publish'),
              "publish-#{event.id}"
            ),
            create_button(
              I18n.t('buttons.delete'),
              "delete-#{event.id}"
            )
          ]
        ]
        
        markup = create_keyboard(buttons)
        send_html_message(message, { reply_markup: markup })
      end
      
      private
      
      def update_event_weather(event, coordinates, city_name)
        require_relative '../../services/weather_service'
        
        lat, lon = coordinates.split(',')
        weather_data = WeatherService.fetch_weather_for_event(coordinates, event.date, event.time)
        
        if weather_data
          event.update(
            weather_city: city_name,
            latitude: lat.to_f,
            longitude: lon.to_f,
            weather_data: weather_data,
            weather_updated_at: Time.current
          )
        else
          event.update(
            weather_city: city_name,
            latitude: lat.to_f,
            longitude: lon.to_f
          )
        end
      end
      
      def transition_to_state(state)
        @session.state = state
        @session.edit_event_id = nil
        @session.save_session
      end
    end
  end
end