module Notifications
  class TelegramGateway
    def initialize(bot)
      @api = bot.api
    end

    def send_message(**attributes)
      @api.send_message(**attributes)
    end

    def edit_message_text(**attributes)
      @api.edit_message_text(**attributes)
    end
  end
end
