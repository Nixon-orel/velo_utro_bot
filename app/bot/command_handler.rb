module Bot
  class CommandHandler < BaseHandler
    def execute
      raise NotImplementedError, "#{self.class} должен реализовать метод #execute"
    end
    
    def ensure_private_chat
      return true if @message.chat.type == 'private'
      
      false
    end
  end
end