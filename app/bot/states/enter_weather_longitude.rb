module Bot
  module States
    class EnterWeatherLongitude < Bot::StateHandler
      def process
        longitude = @message.text.strip
        
        if valid_longitude?(longitude)
          if @session.edit_event_id
            event = Event.find_by(id: @session.edit_event_id)
            unless event
              send_message(I18n.t('invalid_input'))
              return
            end
            latitude = @session.new_event ? @session.new_event['latitude'] : event.latitude
            update_existing_event_weather(event, latitude, longitude.to_f)
          else
            save_event_attribute('longitude', longitude.to_f)
            latitude = @session.new_event['latitude']
            coordinates = "#{latitude},#{longitude}"
            city_name = I18n.t('custom_coordinates')
            fetch_weather_and_save(coordinates, city_name)
          end
        else
          send_message(I18n.t('invalid_longitude'))
        end
      end
      
      private
      
      def valid_longitude?(lon_str)
        return false unless lon_str.match?(/\A-?\d+\.?\d*\z/)
        
        lon = lon_str.to_f
        lon >= -180 && lon <= 180
      end
      
      def fetch_weather_and_save(coordinates, city_name)
        require_relative '../../services/event_weather_service'
        
        result = EventWeatherService.create_event_with_weather(
          @session,
          coordinates,
          city_name,
          expected_state: 'enter_weather_longitude'
        )
        unless result.success?
          return if %i[already_processed already_processing claim_lost].include?(result.error_code)

          AppLogger.error(
            'Bot::States::EnterWeatherLongitude',
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
        
        if result.metadata[:weather_available]
          message = I18n.t('event_created_with_weather', weather_info: result.metadata[:weather_info])
          send_message(message, { reply_markup: markup })
        else
          send_message(I18n.t('event_created_weather_failed'), { reply_markup: markup })
        end
      end
      
      def update_existing_event_weather(event, latitude, longitude)
        unless Events::Policy.manage?(event: event, actor: @user)
          send_message(I18n.t('not_author'))
          return
        end

        require_relative '../../services/weather_service'
        
        coordinates = "#{latitude},#{longitude}"
        city_name = I18n.t('custom_coordinates')
        
        weather_data = WeatherService.fetch_weather_for_event(coordinates, event.date, event.time)
        
        result = Events::EditEvent.call(
          event: event,
          actor: @user,
          changes: {
            weather_city: city_name,
            latitude: latitude,
            longitude: longitude,
            weather_data: weather_data || {},
            weather_updated_at: weather_data ? AppClock.now : nil
          }
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
        
        transition_to_state(nil)
        
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
    end
  end
end
