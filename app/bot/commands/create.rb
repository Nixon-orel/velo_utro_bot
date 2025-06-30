module Bot
  module Commands
    class Create < Bot::CommandHandler
      def execute
        return unless ensure_private_chat
        
        puts "DEBUG: Creating event for user ID: #{@user.id} (type: #{@user.id.class}), Telegram ID: #{@user.telegram_id}"
        
        @session.state = 'choose_date'
        @session.new_event = { 'author_id' => @user.id }
        @session.calendar_type = 'create'
        @session.save_session
        
        calendar = Bot::Helpers::Calendar.new
        calendar.send_to(@bot, @chat_id)
      end
    end
  end
end