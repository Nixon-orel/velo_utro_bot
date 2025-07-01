module Bot
  module Callbacks
    class Find_all
      def initialize(bot, callback, session)
        @bot = bot
        @callback = callback
        @session = session
        @chat_id = callback.message.chat.id
        @message_id = callback.message.message_id
      end
      
      def process
        @bot.api.answer_callback_query(callback_query_id: @callback.id)
        events = Event.upcoming
        
        handler = Bot::CallbackHandler.new(@bot, @callback, @session)
        handler.send(:display_events, events, I18n.t('buttons.find_all'), I18n.t('no_upcoming_events'))
      end
    end
  end
end
