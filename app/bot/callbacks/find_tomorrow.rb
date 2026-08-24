module Bot
  module Callbacks
    class FindTomorrow < Bot::CallbackHandler
      def process
        answer_callback_query
        
        now = AppClock.now
        events = Event.upcoming_on_date(now.to_date + 1, now: now)
        
        display_events(events, I18n.t('buttons.find_tomorrow'), I18n.t('no_events_tomorrow'))
      end
    end
  end
end
