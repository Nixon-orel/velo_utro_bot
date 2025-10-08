module Bot
  module States
    class ChooseWeatherCity < Bot::StateHandler
      def process
        choice = @message.text.strip
        
        case choice
        when '1'
          coordinates = ENV['DEFAULT_WEATHER_COORDINATES'] || '52.9651,36.0785'
          city_name = ENV['DEFAULT_WEATHER_CITY_NAME'] || 'Орёл'
          fetch_weather_and_save(coordinates, city_name)
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
        remove_keyboard = remove_reply_keyboard
        
        if result[:success]
          message = I18n.t('event_created_with_weather', weather_info: result[:weather_info])
          send_message(message, { reply_markup: remove_keyboard })
          send_message("🎉", { reply_markup: markup })
        else
          send_message(I18n.t('event_created_weather_failed'), { reply_markup: remove_keyboard })
          send_message("🎉", { reply_markup: markup })
        end
      end
    end
  end
end