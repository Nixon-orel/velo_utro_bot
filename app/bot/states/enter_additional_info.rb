module Bot
  module States
    class EnterAdditionalInfo < Bot::StateHandler
      def process
        additional_info = @message.text
        additional_info = nil if additional_info == '-'
        
        save_event_attribute('additional_info', additional_info)
        
        if ENV['WEATHER_ENABLED'] == 'true'
          default_coordinates = ENV['DEFAULT_WEATHER_COORDINATES'] || '52.9651,36.0785'
          default_city = ENV['DEFAULT_WEATHER_CITY_NAME'] || 'Орёл'
          
          require_relative '../../services/event_weather_service'
          result = EventWeatherService.create_event_with_weather(@session, default_coordinates, default_city)
          
          transition_to_state(nil)
          
          buttons = [
            [
              create_button(
                I18n.t('buttons.publish'),
                "publish-#{result[:event].id}"
              )
            ]
          ]
          
          buttons << [
            create_button(
              "📍 Изменить город для прогноза",
              "change_weather_city-#{result[:event].id}"
            )
          ]
          
          markup = create_keyboard(buttons)
          
          if result[:success]
            message = I18n.t('event_created_with_weather', weather_info: result[:weather_info])
            send_message(message, { reply_markup: markup })
          else
            send_message(I18n.t('event_created_weather_failed'), { reply_markup: markup })
          end
        else
          event = save_event
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
      
      def save_event
        event = Event.new(
          date: Date.parse(@session.new_event['date']),
          time: @session.new_event['time'],
          event_type: @session.new_event['type'],
          location: @session.new_event['location'],
          distance: @session.new_event['distance'],
          pace: @session.new_event['pace'],
          track: @session.new_event['track'],
          map: @session.new_event['map'],
          additional_info: @session.new_event['additional_info'],
          author_id: @session.new_event['author_id']
        )
        
        event.save
        event
      end
    end
  end
end