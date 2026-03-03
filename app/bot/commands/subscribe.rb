module Bot
  module Commands
    class Subscribe < Bot::CommandHandler
      def execute
        user = get_user(@message)
        
        if user.subscribed_to_notifications
          send_message(I18n.t('already_subscribed'))
        else
          user.update(subscribed_to_notifications: true)
          send_message(I18n.t('subscribed_successfully'))
        end
      end
    end
  end
end
