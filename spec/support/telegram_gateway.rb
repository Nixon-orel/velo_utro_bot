class RecordingTelegramGateway
  attr_reader :messages

  def initialize(message_id: 100, error: nil, errors_by_chat_id: {})
    @message_id = message_id
    @error = error
    @errors_by_chat_id = errors_by_chat_id
    @messages = []
  end

  def send_message(**attributes)
    @messages << attributes
    raise @error if @error
    raise @errors_by_chat_id.fetch(attributes[:chat_id]) if @errors_by_chat_id.key?(attributes[:chat_id])

    Telegram::Bot::Types::Message.new(
      message_id: @message_id,
      date: 1_777_030_400,
      chat: Telegram::Bot::Types::Chat.new(id: -100_123, type: 'channel')
    )
  end
end
