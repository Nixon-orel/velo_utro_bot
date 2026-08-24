require 'integration_helper'
require_relative '../../../app/bot/update_router'

RSpec.describe 'Telegram my events flows' do
  let(:bot_and_api) { recording_bot }
  let(:bot) { bot_and_api.first }
  let(:api) { bot_and_api.last }
  let(:router) { Bot::UpdateRouter.new(bot) }
  let(:telegram_user_record) { telegram_user(id: 101, first_name: 'Никита', username: 'nixon') }
  let(:private_chat) { telegram_chat(id: telegram_user_record.id) }
  let(:callback_message) do
    telegram_message(from: telegram_user_record, chat: private_chat, text: 'My events', message_id: 55)
  end
  let(:user) { create_user(telegram_id: telegram_user_record.id) }

  before do
    AppClock.source = -> { Time.zone.local(2026, 8, 23, 12, 0) }
    use_app_config('ADMIN_IDS' => [])
  end

  it 'shows author and participant sections from the my-events command' do
    send_my_events_command

    buttons = api.sent_messages.last[:reply_markup].inline_keyboard.flatten
    expect(buttons.map(&:callback_data)).to eq(%w[imauthor imparticipant])
  end

  it 'shows only upcoming authored events in start order with matching actions' do
    create_event(author: user, date: today, time: '11:59', location: 'Уже началось')
    current = create_event(
      author: user,
      date: today,
      time: '12:00',
      location: 'Старт сейчас',
      published: false
    )
    published = create_event(
      author: user,
      date: today + 1,
      time: '09:00',
      location: 'Завтра утром',
      published: true
    )
    create_event(
      author: create_user(telegram_id: 202),
      date: today,
      time: '13:00',
      location: 'Чужое событие'
    )

    select_section('imauthor')

    expect(displayed_event_actions).to eq(
      [
        ["edit-#{current.id}", "delete-#{current.id}", "publish-#{current.id}"],
        ["edit-#{published.id}", "delete-#{published.id}"]
      ]
    )
    expect(all_text).not_to include('Уже началось', 'Чужое событие')
  end

  it 'shows only upcoming events where the user is a participant' do
    author = create_user(telegram_id: 202)
    past = create_event(author: author, date: today, time: '11:59', location: 'Уже началось')
    current = create_event(author: author, date: today, time: '12:00', location: 'Старт сейчас')
    future = create_event(author: author, date: today + 1, time: '09:00', location: 'Завтра утром')
    create_event(author: author, date: today, time: '13:00', location: 'Без участия')
    own_event = create_event(author: user, date: today, time: '14:00', location: 'Только автор')
    [past, current, future].each { |event| event.participants << user }

    select_section('imparticipant')

    expect(displayed_event_actions).to eq(
      [["unjoin-#{current.id}"], ["unjoin-#{future.id}"]]
    )
    expect(all_text).not_to include('Уже началось', 'Без участия', own_event.location)
  end

  it 'answers the section callback and removes the category message for an empty result' do
    select_section('imauthor')

    expect(api.callback_answers.last).to eq(callback_query_id: 'callback-1')
    expect(api.deleted_messages.last).to include(chat_id: private_chat.id, message_id: 55)
    expect(api.sent_messages.last[:text]).to eq(I18n.t('no_events'))
  end

  private

  def today
    AppClock.today
  end

  def send_my_events_command
    router.call(telegram_message(from: telegram_user_record, chat: private_chat, text: '/my_events'))
  end

  def select_section(callback_data)
    send_my_events_command
    api.sent_messages.clear
    callback = telegram_callback(
      from: telegram_user_record,
      message: callback_message,
      data: callback_data
    )
    router.call(callback)
  end

  def displayed_event_actions
    api.sent_messages.filter_map do |payload|
      keyboard = payload.dig(:reply_markup)&.inline_keyboard
      keyboard&.flatten&.map(&:callback_data)
    end
  end

  def all_text
    api.sent_messages.map { |payload| payload[:text] }.join("\n")
  end
end
