module Bot
  module Commands
    class MyEvents < Bot::CommandHandler
      def execute
        return unless ensure_private_chat
        
        buttons = create_my_events_buttons
        send_button_message(I18n.t('choose_category'), buttons, { parse_mode: 'HTML' })
      end
    end
  end
end