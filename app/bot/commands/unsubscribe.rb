module Bot
  module Commands
    class Unsubscribe < Bot::CommandHandler
      def execute
        user = get_user(@message)
        
        if user.subscribed_to_notifications
          user.update(subscribed_to_notifications: false)
          send_message(I18n.t('unsubscribed_successfully'))
        else
          send_message(I18n.t('not_subscribed'))
        end
      end
    end
  end
end
