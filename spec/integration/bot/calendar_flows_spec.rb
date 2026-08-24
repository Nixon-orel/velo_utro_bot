require 'integration_helper'
require_relative '../../../app/bot/update_router'

RSpec.describe 'Telegram calendar flows' do
  let(:bot_and_api) { recording_bot }
  let(:bot) { bot_and_api.first }
  let(:api) { bot_and_api.last }
  let(:router) { Bot::UpdateRouter.new(bot) }
  let(:telegram_author) { telegram_user(id: 101, first_name: 'Никита', username: 'nixon') }
  let(:private_chat) { telegram_chat(id: 101) }
  let(:callback_message) do
    telegram_message(from: telegram_author, chat: private_chat, text: 'Calendar', message_id: 55)
  end

  before do
    AppClock.source = -> { Time.zone.local(2026, 8, 22, 12, 0) }
    use_app_config('PUBLIC_CHANNEL_ID' => '@veloutro')
  end

  it 'moves event creation from the calendar to time entry' do
    router.call(telegram_message(from: telegram_author, chat: private_chat, text: '/create'))
    callback = telegram_callback(
      from: telegram_author,
      message: callback_message,
      data: 'calendar_day_2026-08-24'
    )

    router.call(callback)

    session = Session.find_by!(user_id: telegram_author.id.to_s)
    expect(session).to have_attributes(state: 'choose_time')
    expect(session.new_event['date']).to eq('2026-08-24')
    expect(api.callback_answers.last).to eq(callback_query_id: callback.id)
    expect(api.sent_messages.last).to include(text: I18n.t('choose_time'), parse_mode: 'HTML')
  end

  it 'shows events from the date selected for search' do
    author = create_user(telegram_id: 202)
    event = create_event(author: author, date: Date.new(2026, 8, 24), location: 'Парк Победы')
    find_callback = telegram_callback(from: telegram_author, message: callback_message, data: 'find_date')
    router.call(find_callback)
    date_callback = telegram_callback(
      from: telegram_author,
      message: callback_message,
      data: 'calendar_day_2026-08-24',
      id: 'callback-2'
    )

    router.call(date_callback)

    expect(api.sent_messages.map { |payload| payload[:text] }).to include(I18n.t('buttons.find_date') + ':')
    expect(api.sent_messages.last[:text]).to include(event.event_type, 'Парк Победы')
    expect(Session.find_by!(user_id: telegram_author.id.to_s).state).to eq('find_events_on_date')
  end

  it 'updates the date and notifies participants and the channel' do
    author = create_user(telegram_id: telegram_author.id)
    participant = create_user(telegram_id: 202)
    event = create_event(
      author: author,
      date: Date.new(2026, 8, 24),
      published: true,
      channel_message_id: 42
    )
    event.participants << participant
    session = Session.load(telegram_author.id.to_s)
    session.state = 'edit_date'
    session.edit_event_id = event.id
    session.save!
    callback = telegram_callback(
      from: telegram_author,
      message: callback_message,
      data: 'calendar_day_2026-08-25'
    )

    router.call(callback)

    expect(event.reload.date).to eq(Date.new(2026, 8, 25))
    expect(session.reload).to have_attributes(state: nil, edit_event_id: nil)
    expect(api.sent_messages.map { |payload| payload[:chat_id] }).to eq(
      [participant.telegram_id, '@veloutro', private_chat.id, private_chat.id]
    )
    expect(api.sent_messages.last(2).map { |payload| payload[:text] }).to eq(
      [I18n.t('date_saved'), I18n.t('event_updated')]
    )
  end

  it 'does not notify participants or the channel when the selected date is unchanged' do
    author = create_user(telegram_id: telegram_author.id)
    participant = create_user(telegram_id: 202)
    event = create_event(
      author: author,
      date: Date.new(2026, 8, 24),
      published: true,
      channel_message_id: 42
    )
    event.participants << participant
    session = Session.load(telegram_author.id.to_s)
    session.state = 'edit_date'
    session.edit_event_id = event.id
    session.save!
    callback = telegram_callback(
      from: telegram_author,
      message: callback_message,
      data: 'calendar_day_2026-08-24'
    )

    router.call(callback)

    expect(api.sent_messages.map { |payload| payload[:chat_id] }).to eq(
      [private_chat.id, private_chat.id]
    )
    expect(session.reload).to have_attributes(state: nil, edit_event_id: nil)
  end

  it 'resets a date-edit state whose event no longer exists' do
    session = Session.load(telegram_author.id.to_s)
    session.state = 'edit_date'
    session.edit_event_id = 999_999
    session.save!
    callback = telegram_callback(
      from: telegram_author,
      message: callback_message,
      data: 'calendar_day_2026-08-25'
    )

    router.call(callback)

    expect(session.reload).to have_attributes(state: nil, edit_event_id: nil)
    expect(api.callback_answers.last).to eq(callback_query_id: callback.id)
    expect(api.sent_messages.last).to include(
      chat_id: private_chat.id,
      text: I18n.t('invalid_input'),
      parse_mode: 'HTML'
    )
  end

  it 'does not change another author event from a stale date-edit state' do
    event = create_event(
      author: create_user(telegram_id: 202),
      date: Date.new(2026, 8, 24)
    )
    session = Session.load(telegram_author.id.to_s)
    session.state = 'edit_date'
    session.edit_event_id = event.id
    session.save!
    callback = telegram_callback(
      from: telegram_author,
      message: callback_message,
      data: 'calendar_day_2026-08-25'
    )

    router.call(callback)

    expect(event.reload.date).to eq(Date.new(2026, 8, 24))
    expect(session.reload).to have_attributes(state: 'edit_date', edit_event_id: event.id)
    expect(api.sent_messages.last).to include(
      chat_id: private_chat.id,
      text: I18n.t('not_author'),
      parse_mode: 'HTML'
    )
  end
end
