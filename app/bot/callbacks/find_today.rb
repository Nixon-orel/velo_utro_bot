module Bot
  module Callbacks
    class Find_today < Bot::CallbackHandler
      def process
        answer_callback_query
        
        today = Date.today
        tomorrow = today + 1
        events = Event.for_period(today, tomorrow)
        
        display_events(events, I18n.t('buttons.find_today'), I18n.t('no_events_today'))
      end
    end
  end
end
