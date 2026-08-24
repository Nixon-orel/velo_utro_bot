class RecordingTelegramApi
  attr_reader :sent_messages, :edited_messages, :edited_reply_markups, :callback_answers, :deleted_messages

  def initialize(send_errors: [], edit_errors: [])
    @sent_messages = []
    @edited_messages = []
    @edited_reply_markups = []
    @callback_answers = []
    @deleted_messages = []
    @send_errors = send_errors.dup
    @edit_errors = edit_errors.dup
  end

  def send_message(attributes = nil, **keywords)
    payload = normalize_payload(attributes, keywords)
    @sent_messages << payload
    raise @send_errors.shift unless @send_errors.empty?

    response_message(payload)
  end

  def edit_message_text(attributes = nil, **keywords)
    payload = normalize_payload(attributes, keywords)
    @edited_messages << payload
    raise @edit_errors.shift unless @edit_errors.empty?

    response_message(payload)
  end

  def edit_message_reply_markup(attributes = nil, **keywords)
    @edited_reply_markups << normalize_payload(attributes, keywords)
    true
  end

  def answer_callback_query(attributes = nil, **keywords)
    @callback_answers << normalize_payload(attributes, keywords)
    true
  end

  def delete_message(attributes = nil, **keywords)
    @deleted_messages << normalize_payload(attributes, keywords)
    true
  end

  def get_me
    {
      'ok' => true,
      'result' => {
        'id' => 999,
        'is_bot' => true,
        'first_name' => 'Velo Utro',
        'username' => 'TestVeloutroBot'
      }
    }
  end

  private

  def normalize_payload(attributes, keywords)
    (attributes || {}).merge(keywords)
  end

  def response_message(payload)
    chat_id = payload[:chat_id].is_a?(Integer) ? payload[:chat_id] : -100_123
    Telegram::Bot::Types::Message.new(
      message_id: payload[:message_id] || @sent_messages.count + @edited_messages.count,
      date: 1_777_030_400,
      chat: Telegram::Bot::Types::Chat.new(id: chat_id, type: 'private'),
      text: payload[:text].to_s
    )
  end
end

module TelegramUpdates
  def recording_bot(**api_options)
    api = RecordingTelegramApi.new(**api_options)
    [Struct.new(:api).new(api), api]
  end

  def telegram_user(id:, first_name: 'Test user', username: nil)
    attributes = { id: id, is_bot: false, first_name: first_name }
    attributes[:username] = username if username
    Telegram::Bot::Types::User.new(attributes)
  end

  def telegram_chat(id:, type: 'private')
    Telegram::Bot::Types::Chat.new(id: id, type: type)
  end

  def telegram_message(from:, chat:, text: nil, message_id: 10)
    attributes = {
      message_id: message_id,
      date: 1_777_030_400,
      chat: chat,
      from: from
    }
    attributes[:text] = text if text
    Telegram::Bot::Types::Message.new(attributes)
  end

  def telegram_callback(from:, message:, data:, id: 'callback-1')
    Telegram::Bot::Types::CallbackQuery.new(
      id: id,
      from: from,
      message: message,
      chat_instance: 'chat-instance-1',
      data: data
    )
  end
end

RSpec.configure do |config|
  config.include TelegramUpdates
end
