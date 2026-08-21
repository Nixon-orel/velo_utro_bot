module Bot
  class StateHandler < BaseHandler
    def process
      raise NotImplementedError, "#{self.class} должен реализовать метод #process"
    end
    
    def ensure_private_chat
      return true if @message.chat.type == 'private'
      
      false
    end
    
    def validate_input(text, regex)
      !!(text =~ regex)
    end
    
    def save_event_attribute(attribute, value)
      @session.new_event[attribute] = value
    end
    
    def transition_to_state(state)
      @session.state = state
      @session.save_session
    end
    
    def send_next_step_message(message_key, options = {})
      send_html_message(I18n.t(message_key), options)
    end
    
    def create_event_type_buttons
      buttons = []
      APP_CONFIG.event_types.each do |type|
        buttons << [create_button(type, type)]
      end
      buttons
    end
    
    def static_event?(event_type)
      APP_CONFIG.static_events.include?(event_type)
    end
  end
end
