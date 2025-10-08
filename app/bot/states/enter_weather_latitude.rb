module Bot
  module States
    class EnterWeatherLatitude < Bot::StateHandler
      def process
        latitude = @message.text.strip
        
        if valid_latitude?(latitude)
          if @session.edit_event_id
            @session.new_event = {} unless @session.new_event
            @session.new_event['latitude'] = latitude.to_f
            @session.save_session
          else
            save_event_attribute('latitude', latitude.to_f)
          end
          
          transition_to_state('enter_weather_longitude')
          send_message(I18n.t('enter_weather_longitude'))
        else
          send_message(I18n.t('invalid_latitude'))
        end
      end
      
      private
      
      def valid_latitude?(lat_str)
        return false unless lat_str.match?(/\A-?\d+\.?\d*\z/)
        
        lat = lat_str.to_f
        lat >= -90 && lat <= 90
      end
    end
  end
end