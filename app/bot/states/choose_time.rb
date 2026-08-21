module Bot
  module States
    class ChooseTime < Bot::StateHandler
      def process
        time = @message.text
        
        unless EventTime.valid_input?(time)
          send_message(I18n.t('invalid_input'))
          return
        end
        
        save_event_attribute('time', time.strip)
        transition_to_state('choose_type')
        
        buttons = create_event_type_buttons
        markup = create_keyboard(buttons)
        
        send_message(I18n.t('choose_type'), { reply_markup: markup })
      end
    end
  end
end
