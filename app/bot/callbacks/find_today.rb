module Bot
  module Callbacks
    class FindToday < Bot::CallbackHandler
      def process
        answer_callback_query
        
        today = AppClock.today
        events = Event.on_date(today)
        
        display_events(events, I18n.t('buttons.find_today'), I18n.t('no_events_today'))
      end
    end
  end
end
