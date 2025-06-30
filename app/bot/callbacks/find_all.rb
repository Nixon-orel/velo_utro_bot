module Bot
  module Callbacks
    class Find_all
      def initialize(bot, callback, session)
        @bot = bot
        @callback = callback
        @session = session
        @chat_id = callback.message.chat.id
        @message_id = callback.message.message_id
      end
      
      def process
        @bot.api.answer_callback_query(callback_query_id: @callback.id)
        events = Event.upcoming
        event_dates = events.map { |event| event.date.strftime('%Y-%m-%d') }.uniq
        calendar = Bot::Helpers::Calendar.new(lock_date: true)
        today = Date.today
        end_date = today + 180
        
        all_dates = []
        current_date = today
        while current_date <= end_date
          all_dates << current_date.strftime('%Y-%m-%d')
          current_date += 1
        end
        
        calendar.lock_date_array = all_dates - event_dates
        
        @session.state = 'find_events_on_date'
        @session.calendar_type = 'find'
        @session.save_session
        
        calendar.send_to(@bot, @chat_id, I18n.t('calendar.select_date_for_search'))
      end
    end
  end
end
