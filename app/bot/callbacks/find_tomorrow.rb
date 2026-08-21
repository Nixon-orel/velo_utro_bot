module Bot
  module Callbacks
    class FindTomorrow < Bot::CallbackHandler
      def process
        answer_callback_query
        
        tomorrow = AppClock.today + 1
        events = Event.on_date(tomorrow)
        
        display_events(events, I18n.t('buttons.find_tomorrow'), I18n.t('no_events_tomorrow'))
      end
    end
  end
end
