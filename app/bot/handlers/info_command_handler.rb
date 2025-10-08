module Bot
  module Handlers
    class InfoCommandHandler < Bot::CommandHandler
      def execute
        return unless ensure_private_chat
        
        user = User.find_or_create_from_telegram(@message.from)
        message = build_message(user)
        send_html_message(message)
      end
      
      private
      
      def build_message(user)
        message = I18n.t(message_key)
        message += "\n" + I18n.t('admin_commands') if user.admin?
        message
      end
      
      def message_key
        raise NotImplementedError, "#{self.class} должен определить message_key"
      end
    end
  end
end