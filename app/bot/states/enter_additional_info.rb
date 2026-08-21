module Bot
  module States
    class EnterAdditionalInfo < Bot::StateHandler
      def process
        additional_info = @message.text
        additional_info = nil if additional_info == '-'
        
        save_event_attribute('additional_info', additional_info)
        
        if APP_CONFIG.weather_enabled?
          default_coordinates = APP_CONFIG.default_weather_coordinates
          default_city = APP_CONFIG.default_weather_city
          
          require_relative '../../services/event_weather_service'
          result = EventWeatherService.create_event_with_weather(@session, default_coordinates, default_city)
          return handle_creation_failure(result) if result.failure?

          event = result.value
          
          transition_to_state(nil)
          
          buttons = [
            [
              create_button(
                I18n.t('buttons.publish'),
                "publish-#{event.id}"
              )
            ]
          ]
          
          buttons << [
            create_button(
              "📍 Изменить город для прогноза",
              "change_weather_city-#{event.id}"
            )
          ]
          
          markup = create_keyboard(buttons)
          
          if result.metadata[:weather_available]
            message = I18n.t('event_created_with_weather', weather_info: result.metadata[:weather_info])
            send_message(message, { reply_markup: markup })
          else
            send_message(I18n.t('event_created_weather_failed'), { reply_markup: markup })
          end
        else
          result = Events::CreateEvent.from_session(session: @session)
          return handle_creation_failure(result) if result.failure?

          event = result.value
          transition_to_state(nil)
          
          buttons = [
            [
              create_button(
                I18n.t('buttons.publish'),
                "publish-#{event.id}"
              )
            ]
          ]
          
          markup = create_keyboard(buttons)
          send_message(I18n.t('event_created'), { reply_markup: markup })
        end
      end
      
      private
      
      def handle_creation_failure(result)
        AppLogger.error(
          'Bot::States::EnterAdditionalInfo',
          'Failed to create event',
          error_code: result.error_code,
          exception: result.error
        )
        send_message(I18n.t('invalid_input'))
      end
    end
  end
end
