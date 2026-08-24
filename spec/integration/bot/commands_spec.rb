require 'integration_helper'
require_relative '../../../app/bot/update_router'

RSpec.describe 'Telegram command flows' do
  let(:bot_and_api) { recording_bot }
  let(:bot) { bot_and_api.first }
  let(:api) { bot_and_api.last }
  let(:router) { Bot::UpdateRouter.new(bot) }
  let(:telegram_user_record) { telegram_user(id: 101, first_name: 'Никита', username: 'nixon') }
  let(:private_chat) { telegram_chat(id: 101) }

  before do
    use_app_config('PUBLIC_CHANNEL_ID' => '@veloutro', 'ADMIN_IDS' => [])
  end

  it 'shows all private informational commands and reuses one Telegram user' do
    expect do
      router.call(command_message('/start'))
      router.call(command_message('/menu'))
      router.call(command_message('/help'))
    end.to change(User, :count).by(1)

    expect(api.sent_messages.map { |payload| payload[:text] }).to eq(
      [I18n.t('start'), I18n.t('menu'), I18n.t('help')]
    )
    expect(api.sent_messages).to all(include(chat_id: private_chat.id, parse_mode: 'HTML'))
  end

  it 'adds the administrator command section only for an administrator' do
    use_admin_config

    router.call(command_message('/menu'))

    expect(api.sent_messages.last).to include(
      chat_id: private_chat.id,
      text: "#{I18n.t('menu')}\n#{I18n.t('admin_commands')}",
      parse_mode: 'HTML'
    )
  end

  it 'treats the removed announcement command as unknown for an administrator' do
    use_admin_config

    router.call(command_message('/announcement'))

    expect(api.sent_messages).to contain_exactly(
      include(chat_id: private_chat.id, text: I18n.t('unknown_command'))
    )
  end

  it 'returns the same access-denied response for protected status commands' do
    router.call(command_message('/weather_status'))
    router.call(command_message('/scheduler_status'))
    router.call(command_message('/statistics'))

    expect(api.sent_messages.map { |payload| payload[:text] }).to eq(
      [I18n.t('admin_only'), I18n.t('admin_only'), I18n.t('admin_only')]
    )
  end

  it 'shows scheduler runtime details to an administrator' do
    use_app_config('PUBLIC_CHANNEL_ID' => '@veloutro', 'ADMIN_IDS' => [telegram_user_record.id.to_s])

    router.call(command_message('/scheduler_status'))

    expect(api.sent_messages.last).to include(chat_id: private_chat.id)
    expect(api.sent_messages.last[:text]).to include(
      '🤖 Статус планировщика:',
      '🔔 Ежедневные анонсы:',
      '📆 День месячной статистики:',
      '📢 Последний анонс:',
      "🌍 Часовой пояс: #{APP_CONFIG.timezone}",
      "🔢 PID: #{Process.pid}"
    )
  end

  it 'shows disabled weather diagnostics without calling WeatherAPI' do
    use_admin_config('WEATHER_ENABLED' => false, 'WEATHER_API_KEY' => nil)
    AppClock.source = -> { Time.zone.local(2026, 8, 22, 12, 0) }
    author = create_user(telegram_id: 202)
    event = create_event(author: author, published: true)
    NotificationDelivery.create!(
      event: event,
      recipient: author,
      notification_type: 'weather.critical_24h',
      context_key: Bot::Helpers::WeatherNotifier.context_key(event),
      idempotency_key: "weather:#{event.id}:status-failed:user:#{author.id}",
      chat_id: author.telegram_id,
      payload: { text: 'Failed alert', parse_mode: 'HTML' },
      status: 'failed',
      attempts: NotificationDelivery::MAX_ATTEMPTS,
      last_error: 'Faraday::TimeoutError: timeout',
      created_at: AppClock.now,
      updated_at: AppClock.now
    )
    stale_event = create_event(author: author, published: true)
    stale_context = Bot::Helpers::WeatherNotifier.context_key(stale_event)
    NotificationDelivery.create!(
      event: stale_event,
      recipient: author,
      notification_type: 'weather.critical_24h',
      context_key: stale_context,
      idempotency_key: "weather:#{stale_event.id}:status-stale:user:#{author.id}",
      chat_id: author.telegram_id,
      payload: { text: 'Stale failed alert', parse_mode: 'HTML' },
      status: 'failed',
      attempts: NotificationDelivery::MAX_ATTEMPTS,
      last_error: 'Faraday::TimeoutError: timeout',
      created_at: AppClock.now,
      updated_at: AppClock.now
    )
    stale_event.update!(date: stale_event.date + 1.day)

    router.call(command_message('/weather_status'))

    expect(api.sent_messages.last).to include(chat_id: private_chat.id, parse_mode: 'HTML')
    expect(api.sent_messages.last[:text]).to include(
      'Статус погодной системы',
      '❌ Отключен (WEATHER_ENABLED != true)',
      '📨 Ожидают доставки: 0',
      '⚠️ Актуальных ошибок доставки: 1',
      '🗄 Исторических ошибок доставки: 1',
      "🎯 События с ошибками: #{event.id}",
      '🕐 Самая ранняя ошибка: 22.08.2026 12:00',
      '❌ API ключ не установлен'
    )
    expect(a_request(:any, /weatherapi/)).not_to have_been_made
  end

  it 'shows scheduler and real WeatherService diagnostics from a stubbed HTTP response' do
    use_admin_config(
      'WEATHER_ENABLED' => true,
      'WEATHER_API_KEY' => 'status-weather-key',
      'DEFAULT_WEATHER_COORDINATES' => '52.9651, 36.0785',
      'DEFAULT_WEATHER_CITY_NAME' => 'Орёл'
    )
    AppClock.source = -> { Time.zone.local(2026, 8, 24, 12, 0) }
    WeatherService.reset_client!
    request = stub_request(:get, 'https://api.weatherapi.com/v1/forecast.json')
              .with(
                query: {
                  key: 'status-weather-key',
                  q: '52.9651,36.0785',
                  days: 14,
                  aqi: 'no',
                  lang: 'ru'
                }
              )
              .to_return(status: 200, body: weather_api_response)

    router.call(command_message('/weather_status'))

    expect(request).to have_been_requested.once
    expect(api.sent_messages.last[:text]).to include(
      '❌ Не инициализирован',
      '✅ Доступен',
      '🏙️ Орёл: Ясно, 18.5°C',
      '⏱️ Время ответа:'
    )
  end

  it 'sends the previous month statistics to an administrator' do
    use_admin_config
    AppClock.source = -> { Time.zone.local(2026, 1, 15, 12, 0) }
    create_event(
      author: create_user(telegram_id: 202, nickname: 'organizer'),
      date: Date.new(2025, 12, 20),
      distance: '25 км'
    )

    router.call(command_message('/statistics'))

    expect(api.sent_messages.last).to include(
      chat_id: private_chat.id,
      parse_mode: 'HTML'
    )
    expect(api.sent_messages.last[:text]).to include(
      'Статистика велобота за Декабрь 2025',
      'Создано велособытий: <b>1</b>',
      'Прокатано километров: <b>25 км</b>',
      '@organizer'
    )
  end

  it 'reports a statistics delivery failure to an administrator' do
    use_admin_config
    failing_bot, failing_api = recording_bot(send_errors: [Faraday::TimeoutError.new('timeout')])

    Bot::UpdateRouter.new(failing_bot).call(command_message('/statistics'))

    expect(failing_api.sent_messages.length).to eq(2)
    expect(failing_api.sent_messages.first).to include(
      chat_id: private_chat.id,
      parse_mode: 'HTML'
    )
    expect(failing_api.sent_messages.last).to include(
      chat_id: private_chat.id,
      text: '❌ Ошибка при генерации статистики: timeout'
    )
  end

  it 'unsubscribes idempotently' do
    user = create_user(telegram_id: telegram_user_record.id, subscribed_to_notifications: true)

    router.call(command_message('/unsubscribe'))
    router.call(command_message('/unsubscribe'))

    expect(user.reload).not_to be_subscribed_to_notifications
    expect(api.sent_messages.map { |payload| payload[:text] }).to eq(
      [I18n.t('unsubscribed_successfully'), I18n.t('not_subscribed')]
    )
  end

  def command_message(text)
    telegram_message(from: telegram_user_record, chat: private_chat, text: text)
  end

  def use_admin_config(values = {})
    use_app_config(
      {
        'PUBLIC_CHANNEL_ID' => '@veloutro',
        'ADMIN_IDS' => [telegram_user_record.id.to_s]
      }.merge(values)
    )
  end

  def weather_api_response
    JSON.generate(
      'forecast' => {
        'forecastday' => [
          {
            'date' => '2026-08-24',
            'hour' => [
              {
                'time' => '2026-08-24 12:00',
                'temp_c' => 18.5,
                'feelslike_c' => 18.0,
                'condition' => { 'text' => 'Ясно', 'icon' => '//icon' },
                'wind_kph' => 5.0,
                'wind_dir' => 'W',
                'precip_mm' => 0.0,
                'chance_of_rain' => 0,
                'humidity' => 50,
                'uv' => 3
              }
            ],
            'day' => {},
            'astro' => { 'sunrise' => '05:00 AM', 'sunset' => '08:00 PM' }
          }
        ]
      },
      'alerts' => { 'alert' => [] }
    )
  end
end
