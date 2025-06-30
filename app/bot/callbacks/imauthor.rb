module Bot
  module Callbacks
    class Imauthor
      def initialize(bot, callback, session)
        @bot = bot
        @callback = callback
        @session = session
        @chat_id = callback.message.chat.id
        @message_id = callback.message.message_id
      end
      
      def process
        return unless @callback.message.chat.type == 'private'
        user = User.find_or_create_from_telegram(@callback.from)
        today = Date.today
        events = Event.where(author_id: user.id).where('date >= ?', today).order(date: :asc)
        @bot.api.delete_message(
          chat_id: @chat_id,
          message_id: @message_id
        )
        
        if events.empty?
          @bot.api.send_message(
            chat_id: @chat_id,
            text: I18n.t('no_events')
          )
        else
          events.each do |event|
            message = Bot::Helpers::Formatter.event_info(event)
            
            buttons = [
              [
                Telegram::Bot::Types::InlineKeyboardButton.new(
                  text: I18n.t('buttons.edit'),
                  callback_data: "edit-#{event.id}"
                )
              ],
              [
                Telegram::Bot::Types::InlineKeyboardButton.new(
                  text: I18n.t('buttons.delete'),
                  callback_data: "delete-#{event.id}"
                )
              ],
              [
                Telegram::Bot::Types::InlineKeyboardButton.new(
                  text: I18n.t('buttons.publish'),
                  callback_data: "publish-#{event.id}"
                )
              ]
            ]
            
            markup = Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: buttons)
            @bot.api.send_message(
              chat_id: @chat_id,
              text: message,
              parse_mode: 'HTML',
              reply_markup: markup
            )
          end
        end
      end
    end
  end
end
