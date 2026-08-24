require 'integration_helper'
require_relative '../../../app/bot/update_router'

RSpec.describe 'Telegram callback flows' do
  let(:telegram_author) { telegram_user(id: 101, first_name: 'Никита', username: 'nixon') }
  let(:private_chat) { telegram_chat(id: 101) }
  let(:callback_message) do
    telegram_message(from: telegram_author, chat: private_chat, text: 'Event', message_id: 55)
  end

  before do
    use_app_config('PUBLIC_CHANNEL_ID' => '@veloutro', 'ADMIN_IDS' => [])
  end

  it 'publishes and notifies subscribers only once after a repeated callback' do
    bot, api = recording_bot
    router = Bot::UpdateRouter.new(bot)
    author = create_user(telegram_id: telegram_author.id)
    subscriber = create_user(telegram_id: 202, subscribed_to_notifications: true)
    event = create_event(author: author, published: false)
    callback = telegram_callback(
      from: telegram_author,
      message: callback_message,
      data: "publish-#{event.id}"
    )

    router.call(callback)
    router.call(callback)

    expect(event.reload).to have_attributes(published: true, channel_message_id: 1)
    expect(api.sent_messages.map { |payload| payload[:chat_id] }).to eq(
      ['@veloutro', subscriber.telegram_id]
    )
    expect(api.callback_answers.map { |payload| payload[:text] }).to eq(
      [I18n.t('event_published'), 'Событие уже опубликовано']
    )
  end

  it 'keeps an event unpublished and reports a Telegram delivery failure' do
    bot, api = recording_bot(send_errors: [Faraday::TimeoutError.new('timeout')])
    author = create_user(telegram_id: telegram_author.id)
    event = create_event(author: author, published: false)
    callback = telegram_callback(
      from: telegram_author,
      message: callback_message,
      data: "publish-#{event.id}"
    )

    Bot::UpdateRouter.new(bot).call(callback)

    expect(event.reload).not_to be_published
    expect(api.sent_messages.map { |payload| payload[:chat_id] }).to eq(['@veloutro'])
    expect(api.callback_answers.last).to include(
      text: I18n.t('publish_error'),
      show_alert: true
    )
  end

  it 'rejects editing another author event without changing the session' do
    bot, api = recording_bot
    author = create_user(telegram_id: 202)
    event = create_event(author: author)
    callback = telegram_callback(
      from: telegram_author,
      message: callback_message,
      data: "edit-#{event.id}"
    )

    Bot::UpdateRouter.new(bot).call(callback)

    expect(Session.find_by!(user_id: telegram_author.id.to_s).state).to be_nil
    expect(api.sent_messages).to be_empty
    expect(api.callback_answers.last).to include(
      text: I18n.t('not_author'),
      show_alert: true
    )
  end

  it 'updates a private event message only for the first repeated join callback' do
    bot, api = recording_bot
    author = create_user(telegram_id: 202)
    event = create_event(author: author)
    callback = telegram_callback(
      from: telegram_author,
      message: callback_message,
      data: "join-#{event.id}"
    )

    router = Bot::UpdateRouter.new(bot)
    router.call(callback)
    router.call(callback)

    participant = User.find_by!(telegram_id: telegram_author.id.to_s)
    expect(event.participants.reload).to contain_exactly(participant)
    expect(api.edited_messages.count).to eq(1)
    expect(api.callback_answers.first[:text]).to eq(I18n.t('event_joined'))
    expect(api.callback_answers.last).not_to have_key(:text)
  end

  it 'removes a participant through a channel callback' do
    bot, api = recording_bot
    author = create_user(telegram_id: 202)
    participant = create_user(telegram_id: telegram_author.id)
    event = create_event(author: author)
    event.participants << participant
    channel = telegram_chat(id: -100_500, type: 'channel')
    channel_message = telegram_message(from: telegram_author, chat: channel, text: 'Event', message_id: 56)
    callback = telegram_callback(
      from: telegram_author,
      message: channel_message,
      data: "unjoin-#{event.id}"
    )

    Bot::UpdateRouter.new(bot).call(callback)

    expect(event.participants.reload).to be_empty
    expect(api.edited_messages.last).to include(chat_id: channel.id, message_id: 56)
    expect(api.callback_answers.last[:text]).to eq(I18n.t('event_unjoined'))
  end

  it 'finishes deletion after one participant notification fails' do
    bot, api = recording_bot(send_errors: [Faraday::TimeoutError.new('timeout')])
    author = create_user(telegram_id: telegram_author.id)
    participant = create_user(telegram_id: 202)
    event = create_event(author: author, published: false)
    event.participants << participant
    callback = telegram_callback(
      from: telegram_author,
      message: callback_message,
      data: "delete-#{event.id}"
    )

    Bot::UpdateRouter.new(bot).call(callback)

    expect(Event.exists?(event.id)).to be(false)
    expect(api.sent_messages.map { |payload| payload[:chat_id] }).to eq([participant.telegram_id])
    expect(api.deleted_messages.last).to include(chat_id: private_chat.id, message_id: 55)
    expect(api.callback_answers.last[:text]).to eq(I18n.t('event_deleted'))
  end

  it 'does not let another user delete an event' do
    bot, api = recording_bot
    author = create_user(telegram_id: 202)
    event = create_event(author: author)
    callback = telegram_callback(
      from: telegram_author,
      message: callback_message,
      data: "delete-#{event.id}"
    )

    Bot::UpdateRouter.new(bot).call(callback)

    expect(Event.exists?(event.id)).to be(true)
    expect(api.sent_messages).to be_empty
    expect(api.deleted_messages).to be_empty
    expect(api.callback_answers.last).to include(
      text: I18n.t('not_author'),
      show_alert: true
    )
  end

  it 'notifies the channel and participants when a future published event is deleted' do
    AppClock.source = -> { Time.zone.local(2026, 8, 24, 12, 0) }
    bot, api = recording_bot
    author = create_user(telegram_id: telegram_author.id)
    participant = create_user(telegram_id: 202)
    event = create_event(
      author: author,
      date: Date.new(2026, 8, 25),
      published: true,
      channel_message_id: 77
    )
    event.participants << participant
    callback = telegram_callback(
      from: telegram_author,
      message: callback_message,
      data: "delete-#{event.id}"
    )

    Bot::UpdateRouter.new(bot).call(callback)

    expect(Event.exists?(event.id)).to be(false)
    expect(api.sent_messages.map { |payload| payload[:chat_id] }).to eq(
      ['@veloutro', participant.telegram_id]
    )
    expect(api.sent_messages.first[:text]).to include(
      'Мероприятие отменено',
      'было отменено организатором'
    )
    expect(api.callback_answers.last[:text]).to eq(I18n.t('event_deleted'))
  end

  it 'does not announce deletion of an already started published event' do
    AppClock.source = -> { Time.zone.local(2026, 8, 24, 12, 0) }
    bot, api = recording_bot
    author = create_user(telegram_id: telegram_author.id)
    event = create_event(
      author: author,
      date: Date.new(2026, 8, 24),
      time: '11:59',
      published: true,
      channel_message_id: 77
    )
    callback = telegram_callback(
      from: telegram_author,
      message: callback_message,
      data: "delete-#{event.id}"
    )

    Bot::UpdateRouter.new(bot).call(callback)

    expect(Event.exists?(event.id)).to be(false)
    expect(api.sent_messages).to be_empty
    expect(api.callback_answers.last[:text]).to eq(I18n.t('event_deleted'))
  end

  it 'answers an unknown callback instead of leaving it pending' do
    bot, api = recording_bot
    callback = telegram_callback(
      from: telegram_author,
      message: callback_message,
      data: 'unsupported-action'
    )

    Bot::UpdateRouter.new(bot).call(callback)

    expect(api.callback_answers.last).to include(
      text: I18n.t('unknown_command'),
      show_alert: true
    )
  end
end
