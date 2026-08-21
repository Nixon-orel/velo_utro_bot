module Bot
  module Callbacks
    class FindWeek < Bot::CallbackHandler
      def process
        answer_callback_query
        
        today = AppClock.today
        events = Event.from_date_through(today, today + 6.days)
        
        display_events(events, I18n.t('buttons.find_week'), I18n.t('no_events_this_week'))
      end
    end
  end
end
