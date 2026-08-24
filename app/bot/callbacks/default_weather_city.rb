module Bot
  module Callbacks
    class DefaultWeatherCity < Bot::CallbackHandler
      def process
        event = get_authorized_event
        return unless event

        default_coordinates = APP_CONFIG.default_weather_coordinates
        default_city = APP_CONFIG.default_weather_city
        
        result = update_event_weather(event, default_coordinates, default_city)
        unless result.success?
          AppLogger.error(
            'Bot::Callbacks::DefaultWeatherCity',
            'Failed to update event weather',
            event_id: event.id,
            error_code: result.error_code,
            exception: result.error
          )
          answer_callback_query(I18n.t('invalid_input'), show_alert: true)
          return
        end

        if event.weather_data.present?
          Bot::Helpers::WeatherScheduler.schedule_weather_updates(event)
        else
          Bot::Helpers::WeatherScheduler.cancel_for(event.id)
        end
        
        transition_to_state(nil)
        callback_message = if event.weather_data.present?
          'Прогноз обновлен'
        else
          'Город обновлен, но прогноз получить не удалось'
        end
        answer_callback_query(callback_message)
        
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
        require_relative '../../services/event_weather_service'

        EventWeatherService.update_event_weather(
          event: event,
          actor: @user,
          coordinates: coordinates,
          city_name: city_name
        )
      end
      
      def transition_to_state(state)
        @session.state = state
        @session.edit_event_id = nil
        @session.save_session
      end
    end
  end
end
