module Notifications
  class TelegramGateway
    def initialize(bot)
      @api = bot.api
    end

    def send_message(**attributes)
      @api.send_message(**attributes)
    end

    def edit_message_text(**attributes)
      reply_markup = attributes[:reply_markup]
      if reply_markup.is_a?(Hash)
        attributes[:reply_markup] = Telegram::Bot::Types::InlineKeyboardMarkup.new(
          reply_markup.deep_symbolize_keys
        )
      end

      @api.edit_message_text(**attributes)
    end
  end
end
