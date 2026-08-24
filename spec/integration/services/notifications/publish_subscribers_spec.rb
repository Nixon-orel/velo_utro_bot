require 'integration_helper'

RSpec.describe Notifications::PublishSubscribers do
  it 'delivers only to subscribed users' do
    author = create_user(telegram_id: 1)
    first_subscriber = create_user(telegram_id: 2, subscribed_to_notifications: true)
    second_subscriber = create_user(telegram_id: 3, subscribed_to_notifications: true)
    create_user(telegram_id: 4, subscribed_to_notifications: false)
    event = create_event(author: author)
    gateway = RecordingTelegramGateway.new

    result = described_class.call(event: event, gateway: gateway, payload: { text: 'New event' })

    expect(result).to be_success
    expect(result.metadata).to include(sent_count: 2, failed_user_ids: [])
    expect(gateway.messages.map { |message| message[:chat_id] }).to contain_exactly(
      first_subscriber.telegram_id,
      second_subscriber.telegram_id
    )
  end

  it 'continues delivery after one subscriber fails' do
    author = create_user(telegram_id: 1)
    failed_subscriber = create_user(telegram_id: 2, subscribed_to_notifications: true)
    successful_subscriber = create_user(telegram_id: 3, subscribed_to_notifications: true)
    event = create_event(author: author)
    gateway = RecordingTelegramGateway.new(
      errors_by_chat_id: { failed_subscriber.telegram_id => Faraday::TimeoutError.new('timeout') }
    )

    result = described_class.call(event: event, gateway: gateway, payload: { text: 'New event' })

    expect(result).to be_success
    expect(result.metadata).to include(
      sent_count: 1,
      failed_user_ids: [failed_subscriber.id]
    )
    expect(gateway.messages.map { |message| message[:chat_id] }).to include(successful_subscriber.telegram_id)
  end
end
