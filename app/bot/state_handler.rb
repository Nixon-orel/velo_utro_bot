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
      CONFIG['EVENT_TYPES'].each do |type|
        buttons << [create_button(type, type)]
      end
      buttons
    end
    
    def static_event?(event_type)
      static_events = CONFIG['STATIC_EVENTS']
      return false unless static_events
      
      if static_events.is_a?(Array)
        static_events.include?(event_type)
      elsif static_events.is_a?(String)
        static_events.split(',').map(&:strip).include?(event_type)
      else
        false
      end
    end
  end
end