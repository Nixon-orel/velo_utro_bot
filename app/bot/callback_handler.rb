module Bot
  class CallbackHandler < BaseHandler
    attr_reader :callback_data, :message_id
    
    def initialize(bot, callback, session)
      super
      @callback_data = callback.data
      @message_id = callback.message.message_id if callback.message
    end
    
    def process
      raise NotImplementedError, "#{self.class} должен реализовать метод #process"
    end
    
    def ensure_private_chat
      return true if @message.message.chat.type == 'private'
      
      false
    end
    
    def get_event_id
      @callback_data.split('-')[1] if @callback_data.include?('-')
    end
    
    def get_event
      event_id = get_event_id
      return nil unless event_id
      
      Event.find_by(id: event_id)
    end
  end
end