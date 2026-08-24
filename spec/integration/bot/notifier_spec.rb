require 'integration_helper'

RSpec.describe Bot::Helpers::Notifier do
  before do
    use_app_config('PUBLIC_CHANNEL_ID' => '@veloutro')
  end

  it 'continues notifying the remaining participants after one delivery fails' do
    bot, api = recording_bot(send_errors: [Faraday::TimeoutError.new('timeout')])
    author = create_user(telegram_id: 1)
    first_participant = create_user(telegram_id: 2)
    second_participant = create_user(telegram_id: 3)
    event = create_event(author: author)
    event.participants << [first_participant, second_participant]

    described_class.new(bot).notify_participants(event, 'location_changed_notification', new_location: 'Парк')

    expect(api.sent_messages.map { |payload| payload[:chat_id] }).to contain_exactly(
      first_participant.telegram_id,
      second_participant.telegram_id
    )
  end

  it 'does not write a change notification to the channel for a draft' do
    bot, api = recording_bot
    author = create_user(telegram_id: 1)
    event = create_event(author: author, published: false)

    described_class.new(bot).notify_channel_about_change(event, 'location_changed_channel_notification')

    expect(api.sent_messages).to be_empty
  end

  it 'writes a change notification to the configured channel for a published event' do
    bot, api = recording_bot
    author = create_user(telegram_id: 1)
    event = create_event(author: author, published: true, channel_message_id: 42)

    described_class.new(bot).notify_channel_about_change(event, 'location_changed_channel_notification')

    expect(api.sent_messages.last).to include(chat_id: '@veloutro', parse_mode: 'HTML')
  end
end
