module Bot
  module States
    class Choose_time < Bot::StateHandler
      def process
        time = @message.text
        
        unless validate_input(time, /^\d{2}:\d{2}(\s?-\s?\d{2}:\d{2})?$/)
          send_message(I18n.t('invalid_input'))
          return
        end
        
        save_event_attribute('time', time)
        transition_to_state('choose_type')
        
        buttons = create_event_type_buttons
        markup = create_keyboard(buttons)
        
        send_message(I18n.t('choose_type'), { reply_markup: markup })
      end
    end
  end
end