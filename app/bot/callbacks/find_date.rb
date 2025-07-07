module Bot
  module Callbacks
    class FindDate
      def initialize(bot, callback, session)
        @bot = bot
        @callback = callback
        @session = session
        @chat_id = callback.message.chat.id
        @message_id = callback.message.message_id
      end
      
      def process
        @bot.api.answer_callback_query(callback_query_id: @callback.id)
        
        calendar = Bot::Helpers::Calendar.new
        @session.state = 'find_events_on_date'
        @session.calendar_type = 'find'
        @session.save_session
        
        calendar.send_to(@bot, @chat_id, I18n.t('calendar.select_date_for_search'))
      end
    end
  end
end