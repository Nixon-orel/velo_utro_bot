require 'integration_helper'
require_relative '../../../app/bot/update_router'

RSpec.describe 'Telegram event editing states' do
  let(:bot_and_api) { recording_bot }
  let(:bot) { bot_and_api.first }
  let(:api) { bot_and_api.last }
  let(:router) { Bot::UpdateRouter.new(bot) }
  let(:telegram_author) { telegram_user(id: 101, first_name: 'Никита', username: 'nixon') }
  let(:private_chat) { telegram_chat(id: 101) }
  let(:callback_message) do
    telegram_message(from: telegram_author, chat: private_chat, text: 'Event', message_id: 55)
  end

  before do
    use_app_config('PUBLIC_CHANNEL_ID' => '@veloutro', 'WEATHER_ENABLED' => false)
  end

  it 'moves from the edit-time callback to a valid saved time' do
    author = create_user(telegram_id: telegram_author.id)
    event = create_event(author: author, time: '09:00')
    router.call(callback("edit_time-#{event.id}"))
    session = Session.find_by!(user_id: telegram_author.id.to_s)

    expect(session).to have_attributes(state: 'edit_time', edit_event_id: event.id)

    router.call(text_message('10:30'))

    expect(event.reload.time).to eq('10:30')
    expect(session.reload).to have_attributes(state: nil, edit_event_id: nil)
    expect(api.sent_messages.last(2).map { |payload| payload[:text] }).to eq(
      [I18n.t('time_saved'), I18n.t('event_updated')]
    )
  end

  it 'keeps the edit-time state after invalid input' do
    author = create_user(telegram_id: telegram_author.id)
    event = create_event(author: author, time: '09:00')
    session = edit_session(event, 'edit_time')

    router.call(text_message('9:30'))

    expect(event.reload.time).to eq('09:00')
    expect(session.reload).to have_attributes(state: 'edit_time', edit_event_id: event.id)
    expect(api.sent_messages.last[:text]).to eq(I18n.t('invalid_input'))
  end

  it 'notifies participants and the channel when optional information is removed' do
    author = create_user(telegram_id: telegram_author.id)
    participant = create_user(telegram_id: 202)
    event = create_event(
      author: author,
      additional_info: 'Берём фонари',
      published: true,
      channel_message_id: 42
    )
    event.participants << participant
    session = edit_session(event, 'edit_info')

    router.call(text_message('-'))

    expect(event.reload.additional_info).to be_nil
    expect(session.reload).to have_attributes(state: nil, edit_event_id: nil)
    expect(api.sent_messages.map { |payload| payload[:chat_id] }).to eq(
      [participant.telegram_id, '@veloutro', private_chat.id, private_chat.id]
    )
  end

  it 'resets an edit state whose event no longer exists' do
    session = Session.load(telegram_author.id.to_s)
    session.state = 'edit_location'
    session.edit_event_id = 999_999
    session.save!

    router.call(text_message('Парк'))

    expect(session.reload).to have_attributes(state: nil, edit_event_id: nil)
    expect(api.sent_messages.last[:text]).to eq(I18n.t('invalid_input'))
  end

  it 'does not change another author event from a stale edit state' do
    author = create_user(telegram_id: 202)
    event = create_event(author: author, location: 'Сквер')
    session = edit_session(event, 'edit_location')

    router.call(text_message('Парк'))

    expect(event.reload.location).to eq('Сквер')
    expect(session.reload).to have_attributes(state: 'edit_location', edit_event_id: event.id)
    expect(api.sent_messages.last[:text]).to eq(I18n.t('not_author'))
  end

  it 'does not offer track or map editing for a static event' do
    author = create_user(telegram_id: telegram_author.id)
    event = create_event(author: author, event_type: '🎲 Настолки')

    router.call(callback("edit-#{event.id}"))

    callback_data = api.sent_messages.last[:reply_markup].inline_keyboard.flatten.map(&:callback_data)
    expect(callback_data).to include("edit_date-#{event.id}", "edit_time-#{event.id}", "edit_info-#{event.id}")
    expect(callback_data).not_to include("edit_track-#{event.id}", "edit_map-#{event.id}")
  end

  it 'rejects a forged track-edit callback for a static event' do
    author = create_user(telegram_id: telegram_author.id)
    event = create_event(author: author, event_type: '🎲 Настолки')

    router.call(callback("edit_track-#{event.id}"))

    expect(Session.find_by!(user_id: telegram_author.id.to_s)).to have_attributes(
      state: nil,
      edit_event_id: nil
    )
    expect(api.sent_messages).to be_empty
    expect(api.callback_answers.last).to include(
      text: I18n.t('invalid_input'),
      show_alert: true
    )
  end

  it 'rejects a forged map-edit callback for a static event' do
    author = create_user(telegram_id: telegram_author.id)
    event = create_event(author: author, event_type: '🎲 Настолки')

    router.call(callback("edit_map-#{event.id}"))

    expect(Session.find_by!(user_id: telegram_author.id.to_s)).to have_attributes(
      state: nil,
      edit_event_id: nil
    )
    expect(api.sent_messages).to be_empty
    expect(api.callback_answers.last).to include(
      text: I18n.t('invalid_input'),
      show_alert: true
    )
  end

  it 'starts track editing for an active event' do
    author = create_user(telegram_id: telegram_author.id)
    event = create_event(author: author, event_type: '🚴‍♀️ Велосипед')

    router.call(callback("edit_track-#{event.id}"))

    expect(Session.find_by!(user_id: telegram_author.id.to_s)).to have_attributes(
      state: 'edit_track',
      edit_event_id: event.id
    )
    expect(api.sent_messages.last[:text]).to eq(
      Mustache.render(I18n.t('edit_track'), { event: event })
    )
    expect(api.callback_answers.last).to eq(callback_query_id: 'callback-1')
  end

  it 'starts map editing for an active event' do
    author = create_user(telegram_id: telegram_author.id)
    event = create_event(author: author, event_type: '🚴‍♀️ Велосипед')

    router.call(callback("edit_map-#{event.id}"))

    expect(Session.find_by!(user_id: telegram_author.id.to_s)).to have_attributes(
      state: 'edit_map',
      edit_event_id: event.id
    )
    expect(api.sent_messages.last[:text]).to eq(
      Mustache.render(I18n.t('edit_map'), { event: event })
    )
    expect(api.callback_answers.last).to eq(callback_query_id: 'callback-1')
  end

  it 'starts date editing with a calendar for the author' do
    author = create_user(telegram_id: telegram_author.id)
    event = create_event(author: author)

    router.call(callback("edit_date-#{event.id}"))

    expect(Session.find_by!(user_id: telegram_author.id.to_s)).to have_attributes(
      state: 'edit_date',
      edit_event_id: event.id,
      calendar_type: 'edit'
    )
    expect(api.sent_messages.length).to eq(2)
    expect(api.sent_messages.first[:text]).to eq(
      Mustache.render(I18n.t('edit_date'), { event: event })
    )
    expect(api.sent_messages.last[:reply_markup]).to be_a(Telegram::Bot::Types::InlineKeyboardMarkup)
    expect(api.callback_answers.last).to eq(callback_query_id: 'callback-1')
  end

  it 'starts location editing for the author' do
    author = create_user(telegram_id: telegram_author.id)
    event = create_event(author: author, location: 'Сквер')

    router.call(callback("edit_location-#{event.id}"))

    expect(Session.find_by!(user_id: telegram_author.id.to_s)).to have_attributes(
      state: 'edit_location',
      edit_event_id: event.id
    )
    expect(api.sent_messages.last[:text]).to eq(
      Mustache.render(I18n.t('edit_location'), { event: event })
    )
    expect(api.callback_answers.last).to eq(callback_query_id: 'callback-1')
  end

  it 'starts additional-information editing for the author' do
    author = create_user(telegram_id: telegram_author.id)
    event = create_event(author: author)

    router.call(callback("edit_info-#{event.id}"))

    expect(Session.find_by!(user_id: telegram_author.id.to_s)).to have_attributes(
      state: 'edit_info',
      edit_event_id: event.id
    )
    expect(api.sent_messages.last).to include(
      text: I18n.t('edit_info'),
      parse_mode: 'HTML'
    )
    expect(api.callback_answers.last).to eq(callback_query_id: 'callback-1')
  end

  it 'keeps location editing active when the new location is empty' do
    author = create_user(telegram_id: telegram_author.id)
    event = create_event(author: author, location: 'Сквер')
    session = edit_session(event, 'edit_location')

    router.call(text_message(''))

    expect(event.reload.location).to eq('Сквер')
    expect(session.reload).to have_attributes(state: 'edit_location', edit_event_id: event.id)
    expect(api.sent_messages.last[:text]).to eq(I18n.t('invalid_input'))
  end

  it 'keeps date editing active for a message without text' do
    author = create_user(telegram_id: telegram_author.id)
    event = create_event(author: author)
    session = edit_session(event, 'edit_date')

    router.call(telegram_message(from: telegram_author, chat: private_chat))

    expect(session.reload).to have_attributes(state: 'edit_date', edit_event_id: event.id)
    expect(api.sent_messages.last).to include(
      chat_id: private_chat.id,
      text: I18n.t('invalid_input')
    )
  end

  it 'keeps date editing active when the user types a date instead of using the calendar' do
    author = create_user(telegram_id: telegram_author.id)
    event = create_event(author: author, date: Date.new(2026, 8, 24))
    session = edit_session(event, 'edit_date')

    router.call(text_message('25.08.2026'))

    expect(event.reload.date).to eq(Date.new(2026, 8, 24))
    expect(session.reload).to have_attributes(state: 'edit_date', edit_event_id: event.id)
    expect(api.sent_messages.last).to include(
      chat_id: private_chat.id,
      text: I18n.t('invalid_input')
    )
  end

  def edit_session(event, state)
    session = Session.load(telegram_author.id.to_s)
    session.state = state
    session.edit_event_id = event.id
    session.save!
    session
  end

  def text_message(text)
    telegram_message(from: telegram_author, chat: private_chat, text: text)
  end

  def callback(data)
    telegram_callback(from: telegram_author, message: callback_message, data: data)
  end
end
