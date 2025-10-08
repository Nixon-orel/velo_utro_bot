module Bot
  module States
    class EnterWeatherLongitude < Bot::StateHandler
      def process
        longitude = @message.text.strip
        
        if valid_longitude?(longitude)
          if @session.edit_event_id
            event = Event.find(@session.edit_event_id)
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
        
        result = EventWeatherService.create_event_with_weather(@session, coordinates, city_name)
        transition_to_state(nil)
        
        buttons = [
          [
            create_button(
              I18n.t('buttons.publish'),
              "publish-#{result[:event].id}"
            )
          ]
        ]
        
        markup = create_keyboard(buttons)
        
        if result[:success]
          message = I18n.t('event_created_with_weather', weather_info: result[:weather_info])
          send_message(message, { reply_markup: markup })
        else
          send_message(I18n.t('event_created_weather_failed'), { reply_markup: markup })
        end
      end
      
      def update_existing_event_weather(event, latitude, longitude)
        require_relative '../../services/weather_service'
        
        coordinates = "#{latitude},#{longitude}"
        city_name = I18n.t('custom_coordinates')
        
        weather_data = WeatherService.fetch_weather_for_event(coordinates, event.date, event.time)
        
        event.update(
          weather_city: city_name,
          latitude: latitude,
          longitude: longitude,
          weather_data: weather_data || {},
          weather_updated_at: Time.current
        )
        
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