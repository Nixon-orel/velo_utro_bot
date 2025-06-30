module Bot
  module Commands
    class Find
      def initialize(bot, message, session)
        @bot = bot
        @message = message
        @session = session
        @chat_id = message.chat.id
      end
      
      def execute
        return unless @message.chat.type == 'private'
        
        buttons = [
          [
            Telegram::Bot::Types::InlineKeyboardButton.new(
              text: I18n.t('buttons.find_today'),
              callback_data: 'find_today'
            )
          ],
          [
            Telegram::Bot::Types::InlineKeyboardButton.new(
              text: I18n.t('buttons.find_tomorrow'),
              callback_data: 'find_tomorrow'
            )
          ],
          [
            Telegram::Bot::Types::InlineKeyboardButton.new(
              text: I18n.t('buttons.find_week'),
              callback_data: 'find_week'
            )
          ],
          [
            Telegram::Bot::Types::InlineKeyboardButton.new(
              text: I18n.t('buttons.find_all'),
              callback_data: 'find_all'
            )
          ]
        ]
        
        markup = Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: buttons)
        
        @bot.api.send_message(
          chat_id: @chat_id,
          text: I18n.t('choose_date'),
          reply_markup: markup
        )
      end
    end
  end
end