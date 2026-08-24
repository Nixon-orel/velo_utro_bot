module Bot
  module States
    class ChooseWeatherCity < Bot::StateHandler
      def process
        choice = @message.text.strip
        
        case choice
        when '1'
          coordinates = APP_CONFIG.default_weather_coordinates
          city_name = APP_CONFIG.default_weather_city
          if @session.edit_event_id
            update_existing_event_weather(coordinates, city_name)
          else
            fetch_weather_and_save(coordinates, city_name)
          end
        when '2'
          transition_to_state('enter_weather_latitude')
          send_message(I18n.t('enter_weather_latitude'))
        else
          send_message(I18n.t('invalid_choice_weather_city'))
        end
      end
      
      private
      
      def fetch_weather_and_save(coordinates, city_name)
        require_relative '../../services/event_weather_service'
        
        result = EventWeatherService.create_event_with_weather(
          @session,
          coordinates,
          city_name,
          expected_state: 'choose_weather_city'
        )
        unless result.success?
          return if %i[already_processed already_processing claim_lost].include?(result.error_code)

          AppLogger.error(
            'Bot::States::ChooseWeatherCity',
            'Failed to create event',
            error_code: result.error_code,
            exception: result.error
          )
          send_message(I18n.t('invalid_input'))
          return
        end

        event = result.value
        
        buttons = [
          [
            create_button(
              I18n.t('buttons.publish'),
              "publish-#{event.id}"
            )
          ]
        ]
        
        markup = create_keyboard(buttons)
        remove_keyboard = remove_reply_keyboard
        
        if result.metadata[:weather_available]
          message = I18n.t('event_created_with_weather', weather_info: result.metadata[:weather_info])
          send_message(message, { reply_markup: remove_keyboard })
          send_message("🎉", { reply_markup: markup })
        else
          send_message(I18n.t('event_created_weather_failed'), { reply_markup: remove_keyboard })
          send_message("🎉", { reply_markup: markup })
        end
      end

      def update_existing_event_weather(coordinates, city_name)
        event = Event.find_by(id: @session.edit_event_id)
        unless event
          send_message(I18n.t('invalid_input'))
          return
        end

        require_relative '../../services/event_weather_service'
        result = EventWeatherService.update_event_weather(
          event: event,
          actor: @user,
          coordinates: coordinates,
          city_name: city_name
        )
        unless result.success?
          message_key = result.error_code == :forbidden ? 'not_author' : 'invalid_input'
          send_message(I18n.t(message_key))
          return
        end

        if event.weather_data.present?
          Bot::Helpers::WeatherScheduler.schedule_weather_updates(event)
        else
          Bot::Helpers::WeatherScheduler.cancel_for(event.id)
        end

        @session.state = nil
        @session.edit_event_id = nil
        @session.save_session

        buttons = [
          [
            create_button(I18n.t('buttons.publish'), "publish-#{event.id}"),
            create_button(I18n.t('buttons.delete'), "delete-#{event.id}")
          ]
        ]
        markup = create_keyboard(buttons)
        send_html_message(Bot::Helpers::Formatter.event_info(event), { reply_markup: markup })
      end
    end
  end
end
