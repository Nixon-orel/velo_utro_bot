module Bot
  module Commands
    class Find < Bot::CommandHandler
      def execute
        return unless ensure_private_chat
        
        buttons = create_find_buttons
        send_button_message(I18n.t('find_events_interval'), buttons)
      end
    end
  end
end