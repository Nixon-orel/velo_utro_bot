module Bot
  module Callbacks
    class FindDate < Bot::CallbackHandler
      def process
        answer_callback_query

        @session.state = 'find_events_on_date'
        @session.calendar_type = 'find'
        @session.save_session

        Bot::Helpers::Calendar.new.send_to(
          @bot,
          @chat_id,
          I18n.t('calendar.select_date_for_search')
        )
      end
    end
  end
end
