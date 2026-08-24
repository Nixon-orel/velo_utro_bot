module Bot
  module Callbacks
    class FindToday < Bot::CallbackHandler
      def process
        answer_callback_query
        
        now = AppClock.now
        events = Event.upcoming_on_date(now.to_date, now: now)
        
        display_events(events, I18n.t('buttons.find_today'), I18n.t('no_events_today'))
      end
    end
  end
end
