require 'integration_helper'
require_relative '../../../app/bot/update_router'

RSpec.describe 'Telegram event search flows' do
  let(:bot_and_api) { recording_bot }
  let(:bot) { bot_and_api.first }
  let(:api) { bot_and_api.last }
  let(:router) { Bot::UpdateRouter.new(bot) }
  let(:telegram_searcher) { telegram_user(id: 101, first_name: 'Никита', username: 'nixon') }
  let(:private_chat) { telegram_chat(id: telegram_searcher.id) }
  let(:callback_message) do
    telegram_message(from: telegram_searcher, chat: private_chat, text: 'Search', message_id: 55)
  end
  let(:author) { create_user(telegram_id: 202) }

  before do
    AppClock.source = -> { Time.zone.local(2026, 8, 23, 12, 0) }
    use_app_config('ADMIN_IDS' => [])
  end

  it 'shows all supported search intervals from the find command' do
    send_find_command

    buttons = api.sent_messages.last[:reply_markup].inline_keyboard.flatten
    expect(buttons.map(&:callback_data)).to eq(
      %w[find_today find_tomorrow find_week find_date find_all]
    )
  end

  it 'shows only events that have not started yet today' do
    create_event(author: author, date: today, time: '11:59', location: 'Уже началось')
    current = create_event(author: author, date: today, time: '12:00', location: 'Старт сейчас')
    later = create_event(author: author, date: today, time: '18:00', location: 'Старт вечером')
    create_event(author: author, date: tomorrow, time: '09:00', location: 'Только завтра')

    search('find_today')

    expect(displayed_event_ids).to eq([current.id, later.id])
    expect(all_text).not_to include('Уже началось', 'Только завтра')
  end

  it 'shows only tomorrow events ordered by start time' do
    later = create_event(author: author, date: tomorrow, time: '18:00', location: 'Завтра вечером')
    earlier = create_event(author: author, date: tomorrow, time: '08:00', location: 'Завтра утром')
    create_event(author: author, date: today + 2, time: '08:00', location: 'Послезавтра')

    search('find_tomorrow')

    expect(displayed_event_ids).to eq([earlier.id, later.id])
    expect(all_text).not_to include('Послезавтра')
  end

  it 'orders a supported legacy time by its parsed start instead of its stored text' do
    legacy_morning = create_event(author: author, date: tomorrow, time: '09:00', location: 'Legacy утром')
    legacy_morning.update_column(:time, '9:00 - 10:00')
    noon = create_event(author: author, date: tomorrow, time: '12:00', location: 'Ровно в полдень')

    search('find_tomorrow')

    expect(displayed_event_ids).to eq([legacy_morning.id, noon.id])
  end

  it 'shows upcoming events through the sixth following day without past or seventh-day events' do
    create_event(author: author, date: today, time: '11:59', location: 'Прошедшее сегодня')
    current = create_event(author: author, date: today, time: '12:00', location: 'Текущее сегодня')
    boundary = create_event(author: author, date: today + 6, time: '23:59', location: 'Граница недели')
    create_event(author: author, date: today + 7, time: '00:00', location: 'За границей недели')

    search('find_week')

    expect(displayed_event_ids).to eq([current.id, boundary.id])
    expect(all_text).not_to include('Прошедшее сегодня', 'За границей недели')
  end

  it 'does not show an already started event when today is selected in the calendar' do
    create_event(author: author, date: today, time: '11:59', location: 'Прошедшее по дате')
    current = create_event(author: author, date: today, time: '12:00', location: 'Текущее по дате')

    send_find_command
    find_date_callback = telegram_callback(
      from: telegram_searcher,
      message: callback_message,
      data: 'find_date'
    )
    router.call(find_date_callback)
    date_callback = telegram_callback(
      from: telegram_searcher,
      message: callback_message,
      data: "calendar_day_#{today}",
      id: 'callback-2'
    )
    router.call(date_callback)

    expect(displayed_event_ids).to eq([current.id])
    expect(all_text).not_to include('Прошедшее по дате')
    expect(api.callback_answers.last).to eq(callback_query_id: date_callback.id)
  end

  it 'returns the period-specific empty result message' do
    search('find_today')

    expect(api.sent_messages.last[:text]).to eq(I18n.t('no_events_today'))
    expect(displayed_event_ids).to be_empty
  end


  it 'uses one time snapshot if midnight passes while processing the search' do
    boundary = create_event(
      author: author,
      date: Date.new(2026, 8, 23),
      time: '23:59',
      location: 'Перед полуночью'
    )
    moments = [
      Time.zone.local(2026, 8, 23, 23, 59),
      Time.zone.local(2026, 8, 24, 0, 0)
    ]
    calls = 0
    AppClock.source = lambda do
      moment = moments.fetch([calls, moments.length - 1].min)
      calls += 1
      moment
    end

    search('find_today')

    expect(displayed_event_ids).to eq([boundary.id])
    expect(calls).to eq(1)
  end

  it 'shows every upcoming event and chooses the participation action for the current user' do
    participant = create_user(telegram_id: telegram_searcher.id)
    create_event(author: author, date: today, time: '11:59', location: 'Уже началось')
    joined = create_event(author: author, date: today, time: '12:00', location: 'Уже участвую')
    available = create_event(author: author, date: tomorrow, time: '09:00', location: 'Можно вступить')
    joined.participants << participant

    search('find_all')

    expect(displayed_event_actions).to eq(
      ["unjoin-#{joined.id}", "join-#{available.id}"]
    )
    expect(all_text).not_to include('Уже началось')
  end

  private

  def today
    AppClock.today
  end

  def tomorrow
    today + 1
  end

  def send_find_command
    router.call(telegram_message(from: telegram_searcher, chat: private_chat, text: '/find'))
  end

  def search(callback_data)
    send_find_command
    callback = telegram_callback(
      from: telegram_searcher,
      message: callback_message,
      data: callback_data
    )
    router.call(callback)
    expect(api.callback_answers.last).to eq(callback_query_id: callback.id)
  end

  def displayed_event_ids
    api.sent_messages.filter_map do |payload|
      callback_data = payload.dig(:reply_markup)&.inline_keyboard&.dig(0, 0)&.callback_data
      callback_data&.delete_prefix('join-')&.to_i if callback_data&.start_with?('join-')
    end
  end

  def displayed_event_actions
    api.sent_messages.filter_map do |payload|
      payload.dig(:reply_markup)&.inline_keyboard&.dig(0, 0)&.callback_data
    end.select { |callback_data| callback_data.start_with?('join-', 'unjoin-') }
  end

  def all_text
    api.sent_messages.map { |payload| payload[:text] }.join("\n")
  end
end
