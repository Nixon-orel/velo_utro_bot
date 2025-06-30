module Bot
  module Callbacks
    class Find_tomorrow < Bot::CallbackHandler
      def process
        answer_callback_query
        
        tomorrow = Date.today + 1
        day_after_tomorrow = tomorrow + 1
        events = Event.for_period(tomorrow, day_after_tomorrow)
        
        display_events(events, I18n.t('buttons.find_tomorrow'), I18n.t('no_events_tomorrow'))
      end
    end
  end
end
