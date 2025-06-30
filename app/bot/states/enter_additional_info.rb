module Bot
  module States
    class Enter_additional_info < Bot::StateHandler
      def process
        additional_info = @message.text
        additional_info = nil if additional_info == '-'
        
        save_event_attribute('additional_info', additional_info)
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