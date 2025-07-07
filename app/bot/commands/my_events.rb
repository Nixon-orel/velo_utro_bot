module Bot
  module Commands
    class MyEvents
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
              text: I18n.t('i_m_author'),
              callback_data: 'imauthor'
            )
          ],
          [
            Telegram::Bot::Types::InlineKeyboardButton.new(
              text: I18n.t('i_m_participant'),
              callback_data: 'imparticipant'
            )
          ]
        ]
        
        markup = Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: buttons)
        
        @bot.api.send_message(
          chat_id: @chat_id,
          text: I18n.t('choose_category'),
          parse_mode: 'HTML',
          reply_markup: markup
        )
      end
    end
  end
end