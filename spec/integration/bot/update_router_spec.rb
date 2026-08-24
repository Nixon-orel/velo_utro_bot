require 'integration_helper'
require_relative '../../../app/bot/update_router'

RSpec.describe Bot::UpdateRouter do
  let(:bot_and_api) { recording_bot }
  let(:bot) { bot_and_api.first }
  let(:api) { bot_and_api.last }
  let(:router) { described_class.new(bot) }
  let(:user) { telegram_user(id: 101, first_name: 'Никита', username: 'nixon') }
  let(:private_chat) { telegram_chat(id: 101) }

  it 'routes a private subscribe command and keeps repeat delivery idempotent' do
    message = telegram_message(from: user, chat: private_chat, text: '/subscribe@TestVeloutroBot')

    router.call(message)
    router.call(message)

    expect(User.find_by!(telegram_id: '101')).to be_subscribed_to_notifications
    expect(api.sent_messages.map { |payload| payload[:text] }).to eq(
      [I18n.t('subscribed_successfully'), I18n.t('already_subscribed')]
    )
  end

  it 'redirects a group command to the configured private bot chat' do
    group_chat = telegram_chat(id: -100_500, type: 'supergroup')
    message = telegram_message(from: user, chat: group_chat, text: '/create')

    router.call(message)

    payload = api.sent_messages.fetch(0)
    button = payload[:reply_markup].inline_keyboard.dig(0, 0)
    expect(payload[:chat_id]).to eq(group_chat.id)
    expect(button.url).to eq('https://t.me/TestVeloutroBot?start=create')
  end

  it 'uses the Telegram bot profile when no username is configured' do
    use_app_config('BOT_USERNAME' => nil)
    group_chat = telegram_chat(id: -100_501, type: 'supergroup')

    router.call(telegram_message(from: user, chat: group_chat, text: '/find'))

    expect(api.sent_messages).to contain_exactly(
      include(
        chat_id: group_chat.id,
        text: 'Для использования команд бота перейдите в личные сообщения с @TestVeloutroBot'
      )
    )
  end

  it 'ignores a message without a sender' do
    message = Telegram::Bot::Types::Message.new(
      message_id: 11,
      date: 1_777_030_400,
      chat: private_chat,
      text: '/start'
    )

    expect do
      router.call(message)
    end.not_to change(Session, :count)

    expect(api.sent_messages).to be_empty
  end

  it 'returns the unknown-command message for private free text without state' do
    message = telegram_message(from: user, chat: private_chat, text: 'Привет')

    router.call(message)

    expect(api.sent_messages.last).to include(
      chat_id: private_chat.id,
      text: I18n.t('unknown_command')
    )
  end

  it 'routes a valid time through the persisted creation state' do
    session = Session.load(user.id.to_s)
    session.new_event = { 'date' => '2026-08-24' }
    session.state = 'choose_time'
    session.save!
    message = telegram_message(from: user, chat: private_chat, text: '09:30')

    router.call(message)

    session.reload
    expect(session.state).to eq('choose_type')
    expect(session.new_event['time']).to eq('09:30')
    expect(api.sent_messages.last[:text]).to eq(I18n.t('choose_type'))
  end

  it 'keeps the current state after invalid time input' do
    session = Session.load(user.id.to_s)
    session.new_event = { 'date' => '2026-08-24' }
    session.state = 'choose_time'
    session.save!
    message = telegram_message(from: user, chat: private_chat, text: '9:30')

    router.call(message)

    expect(session.reload.state).to eq('choose_time')
    expect(session.new_event['time']).to be_nil
    expect(api.sent_messages.last[:text]).to eq(I18n.t('invalid_input'))
  end

  it 'does not advance a text-entry state for a message without text' do
    session = Session.load(user.id.to_s)
    session.new_event = {
      'date' => '2026-08-24',
      'time' => '09:30',
      'type' => '🚴‍♀️ Велосипед'
    }
    session.state = 'choose_location'
    session.save!

    router.call(telegram_message(from: user, chat: private_chat))

    expect(session.reload.state).to eq('choose_location')
    expect(session.new_event).not_to have_key('location')
    expect(api.sent_messages.last).to include(
      chat_id: private_chat.id,
      text: I18n.t('invalid_input')
    )
  end

  it 'does not process a private creation state from a group message' do
    session = Session.load(user.id.to_s)
    session.new_event = { 'date' => '2026-08-24' }
    session.state = 'choose_time'
    session.save!
    group_chat = telegram_chat(id: -100_502, type: 'supergroup')

    router.call(telegram_message(from: user, chat: group_chat, text: '09:30'))

    expect(session.reload.state).to eq('choose_time')
    expect(session.new_event['time']).to be_nil
    expect(api.sent_messages).to be_empty
  end

  it 'stores a supported event type callback and advances the session' do
    session = Session.load(user.id.to_s)
    session.new_event = { 'date' => '2026-08-24', 'time' => '09:30' }
    session.state = 'choose_type'
    session.save!
    callback_message = telegram_message(from: user, chat: private_chat, text: 'Choose type')
    callback = telegram_callback(
      from: user,
      message: callback_message,
      data: '🚴‍♀️ Велосипед'
    )

    router.call(callback)

    session.reload
    expect(session.state).to eq('choose_location')
    expect(session.new_event['type']).to eq('🚴‍♀️ Велосипед')
    expect(api.sent_messages.last[:text]).to eq(I18n.t('choose_location'))
  end

  it 'finishes event creation from the persisted state without weather' do
    author = create_user(telegram_id: user.id, username: user.username)
    session = Session.load(user.id.to_s)
    session.new_event = {
      'author_id' => author.id,
      'date' => '2026-08-26',
      'time' => '09:30',
      'type' => '🚴‍♀️ Велосипед',
      'location' => 'Орёл'
    }
    session.state = 'enter_additional_info'
    session.save!
    message = telegram_message(from: user, chat: private_chat, text: '-')

    expect do
      router.call(message)
      router.call(message)
    end.to change(Event, :count).by(1)

    event = Event.order(:id).last
    expect(event).to have_attributes(
      author_id: author.id,
      event_type: '🚴‍♀️ Велосипед',
      additional_info: nil
    )
    expect(session.reload.state).to be_nil
    creation_message = api.sent_messages.first
    expect(creation_message[:text]).to eq(I18n.t('event_created'))
    expect(creation_message[:reply_markup].inline_keyboard.dig(0, 0).callback_data)
      .to eq("publish-#{event.id}")
    expect(api.sent_messages.last[:text]).to eq(I18n.t('unknown_command'))
  end

  it 'processes a channel join callback without creating a database session' do
    author = create_user(telegram_id: 202)
    event = create_event(author: author)
    channel = telegram_chat(id: -100_500, type: 'channel')
    callback_message = telegram_message(from: user, chat: channel, text: 'Event', message_id: 55)
    callback = telegram_callback(from: user, message: callback_message, data: "join-#{event.id}")

    expect do
      router.call(callback)
    end.not_to change(Session, :count)

    participant = User.find_by!(telegram_id: user.id.to_s)
    expect(event.participants.reload).to contain_exactly(participant)
    expect(api.callback_answers.last).to include(
      callback_query_id: callback.id,
      text: I18n.t('event_joined')
    )
    expect(api.edited_messages.last[:message_id]).to eq(55)
  end

  it 'answers a stale event callback instead of leaving the Telegram spinner active' do
    callback_message = telegram_message(from: user, chat: private_chat, text: 'Deleted event')
    callback = telegram_callback(from: user, message: callback_message, data: 'join-999999')

    router.call(callback)

    expect(api.callback_answers.last).to include(
      callback_query_id: callback.id,
      text: I18n.t('invalid_input'),
      show_alert: true
    )
  end
end
