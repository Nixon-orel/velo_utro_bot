require 'integration_helper'

RSpec.describe Notifications::TelegramGateway do
  it 'serializes a persisted inline keyboard as Telegram JSON' do
    api = Telegram::Bot::Api.new('test-token', url: 'https://telegram.test')
    bot = Struct.new(:api).new(api)
    expected_markup = {
      'inline_keyboard' => [
        [
          { 'text' => 'Присоединиться', 'callback_data' => 'join-42' },
          { 'text' => 'Отказаться', 'callback_data' => 'unjoin-42' }
        ]
      ]
    }
    request = stub_request(:post, 'https://telegram.test/bottest-token/editMessageText')
              .with do |http_request|
                params = URI.decode_www_form(http_request.body).to_h
                serialized_markup = params['reply_markup']
                serialized_markup && JSON.parse(serialized_markup) == expected_markup
              end
              .to_return(
                status: 200,
                body: {
                  ok: true,
                  result: {
                    message_id: 42,
                    date: 1_777_030_400,
                    chat: { id: -100_123, type: 'channel' },
                    text: 'Event'
                  }
                }.to_json,
                headers: { 'Content-Type' => 'application/json' }
              )

    described_class.new(bot).edit_message_text(
      chat_id: '@veloutro',
      message_id: 42,
      text: 'Event',
      reply_markup: expected_markup
    )

    expect(request).to have_been_requested.once
  end
end
