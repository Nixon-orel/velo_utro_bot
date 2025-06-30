module Bot
  module Commands
    class Help < Bot::CommandHandler
      def execute
        user = User.find_or_create_from_telegram(@message.from)
        
        message = I18n.t('help')
        
        if user.admin?
          message += "\n" + I18n.t('admin_commands')
        end
        
        send_html_message(message)
      end
    end
  end
end