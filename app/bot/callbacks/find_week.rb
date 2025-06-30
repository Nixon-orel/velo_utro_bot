module Bot
  module Callbacks
    class Find_week < Bot::CallbackHandler
      def process
        answer_callback_query
        
        today = Date.today
        next_week = today + 7
        events = Event.for_period(today, next_week)
        
        display_events(events, I18n.t('buttons.find_week'), I18n.t('no_events_this_week'))
      end
    end
  end
end
