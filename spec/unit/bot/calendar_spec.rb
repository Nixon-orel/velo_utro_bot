require 'spec_helper'
require_relative '../../../app/bot/helpers/calendar'
require_relative '../../support/telegram_updates'

RSpec.describe Bot::Helpers::Calendar do
  let(:bot_and_api) { recording_bot }
  let(:bot) { bot_and_api.first }
  let(:api) { bot_and_api.last }
  let(:user) { telegram_user(id: 101) }
  let(:chat) { telegram_chat(id: 101) }
  let(:message) { telegram_message(from: user, chat: chat, text: 'Calendar', message_id: 55) }

  before do
    AppClock.source = -> { Time.zone.local(2026, 8, 22, 12, 0) }
  end

  it 'renders only selectable dates inside the configured range' do
    described_class.new.send_to(bot, chat.id)

    buttons = api.sent_messages.last[:reply_markup].inline_keyboard.flatten
    expect(buttons.find { |button| button.text == '21' }).to be_nil
    expect(buttons.find { |button| button.callback_data == 'calendar_day_2026-08-22' }).not_to be_nil
    expect(buttons.find { |button| button.callback_data == 'calendar_month_2026_9' }).not_to be_nil
    expect(api.sent_messages.last[:text]).to eq(I18n.t('calendar.select_date'))
  end

  it 'disables dates before start_date and after stop_date in the rendered month' do
    calendar = described_class.new(
      start_date: Date.new(2026, 8, 24),
      stop_date: Date.new(2026, 8, 25)
    )

    calendar.send_to(bot, chat.id)

    buttons = api.sent_messages.last[:reply_markup].inline_keyboard.flatten
    callback_data = buttons.map(&:callback_data)
    expect(callback_data).not_to include('calendar_day_2026-08-23')
    expect(callback_data).to include('calendar_day_2026-08-24', 'calendar_day_2026-08-25')
    expect(callback_data).not_to include('calendar_day_2026-08-26')
  end

  it 'returns a selected available date and answers the callback' do
    callback = telegram_callback(from: user, message: message, data: 'calendar_day_2026-08-24')

    result = described_class.new.handle_callback(bot, callback)

    expect(result).to eq('2026-08-24')
    expect(api.callback_answers.last).to eq(callback_query_id: callback.id)
  end

  it 'updates the same message when navigating to another month' do
    callback = telegram_callback(from: user, message: message, data: 'calendar_month_2026_9')

    result = described_class.new.handle_callback(bot, callback)

    expect(result).to be_nil
    expect(api.edited_reply_markups.last).to include(chat_id: chat.id, message_id: message.message_id)
    expect(api.callback_answers.last).to eq(callback_query_id: callback.id)
  end

  it 'rejects a crafted date before the allowed range' do
    callback = telegram_callback(from: user, message: message, data: 'calendar_day_2026-08-21')

    result = described_class.new.handle_callback(bot, callback)

    expect(result).to be_nil
    expect(api.callback_answers.last).to include(
      text: I18n.t('calendar.date_locked'),
      show_alert: true
    )
  end

  it 'answers a malformed date callback with an error' do
    callback = telegram_callback(from: user, message: message, data: 'calendar_day_not-a-date')

    result = described_class.new.handle_callback(bot, callback)

    expect(result).to be_nil
    expect(api.callback_answers.last).to include(text: I18n.t('invalid_input'), show_alert: true)
  end

  it 'answers a date callback without a value with an error' do
    callback = telegram_callback(from: user, message: message, data: 'calendar_day')

    result = described_class.new.handle_callback(bot, callback)

    expect(result).to be_nil
    expect(api.callback_answers.last).to include(text: I18n.t('invalid_input'), show_alert: true)
  end

  it 'answers an incomplete month callback with an error' do
    callback = telegram_callback(from: user, message: message, data: 'calendar_month_2026')

    result = described_class.new.handle_callback(bot, callback)

    expect(result).to be_nil
    expect(api.callback_answers.last).to include(text: I18n.t('invalid_input'), show_alert: true)
  end
end
