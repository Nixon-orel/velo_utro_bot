module Bot
  module Callbacks
    class FindAll < Bot::CallbackHandler
      def process
        answer_callback_query
        display_events(Event.upcoming, I18n.t('buttons.find_all'), I18n.t('no_upcoming_events'))
      end
    end
  end
end
