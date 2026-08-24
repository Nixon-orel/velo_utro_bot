require 'integration_helper'
require_relative '../../../app/bot/update_router'

RSpec.describe 'Telegram weather states and callbacks' do
  let(:bot_and_api) { recording_bot }
  let(:bot) { bot_and_api.first }
  let(:api) { bot_and_api.last }
  let(:router) { Bot::UpdateRouter.new(bot) }
  let(:telegram_author) { telegram_user(id: 101, first_name: 'Никита', username: 'nixon') }
  let(:private_chat) { telegram_chat(id: 101) }
  let(:callback_message) do
    telegram_message(from: telegram_author, chat: private_chat, text: 'Weather', message_id: 55)
  end

  before do
    use_app_config(
      'WEATHER_API_KEY' => 'test-weather-key',
      'WEATHER_ENABLED' => true,
      'PUBLIC_CHANNEL_ID' => '@veloutro'
    )
  end

  it 'keeps the weather-city state after an unsupported choice' do
    session = creation_session(state: 'choose_weather_city')

    expect do
      router.call(text_message('3'))
    end.not_to change(Event, :count)

    expect(session.reload.state).to eq('choose_weather_city')
    expect(api.sent_messages.last[:text]).to eq(I18n.t('invalid_choice_weather_city'))
  end

  it 'moves a custom-city choice to latitude entry' do
    session = creation_session(state: 'choose_weather_city')

    router.call(text_message(' 2 '))

    expect(session.reload.state).to eq('enter_weather_latitude')
    expect(api.sent_messages.last[:text]).to eq(I18n.t('enter_weather_latitude'))
  end

  it 'creates an event with the default-city forecast' do
    session = creation_session(state: 'choose_weather_city')
    weather_request = stub_weather_success(APP_CONFIG.default_weather_coordinates)

    expect do
      router.call(text_message('1'))
    end.to change(Event, :count).by(1)

    event = Event.order(:id).last
    expect(event).to have_attributes(
      weather_city: APP_CONFIG.default_weather_city,
      weather_data: include('temp_c' => 18, 'condition' => 'Ясно')
    )
    expect(session.reload.state).to be_nil
    expect(api.sent_messages[-2][:text]).to include(
      I18n.t('event_created_with_weather', weather_info: '').strip,
      "Погода в г. #{APP_CONFIG.default_weather_city}",
      'Ясно, 18°C'
    )
    expect(api.sent_messages.last[:reply_markup].inline_keyboard.dig(0, 0).callback_data)
      .to eq("publish-#{event.id}")
    expect(weather_request).to have_been_requested.once
  end

  it 'rejects an out-of-range latitude without losing the current state' do
    session = creation_session(state: 'enter_weather_latitude')

    router.call(text_message('-90.1'))

    expect(session.reload.state).to eq('enter_weather_latitude')
    expect(session.new_event).not_to have_key('latitude')
    expect(api.sent_messages.last[:text]).to eq(I18n.t('invalid_latitude'))
  end

  it 'stores a valid latitude and requests longitude' do
    session = creation_session(state: 'enter_weather_latitude')

    router.call(text_message('52.1000'))

    expect(session.reload.state).to eq('enter_weather_longitude')
    expect(session.new_event['latitude']).to eq(52.1)
    expect(api.sent_messages.last[:text]).to eq(I18n.t('enter_weather_longitude'))
  end

  it 'creates one event with custom coordinates when WeatherAPI has no forecast' do
    session = creation_session(state: 'enter_weather_longitude')
    session.new_event = session.new_event.merge('latitude' => 52.1)
    session.save!
    weather_request = stub_weather_failure('52.1,36.2')

    expect do
      router.call(text_message('36.2'))
    end.to change(Event, :count).by(1)

    event = Event.order(:id).last
    expect(event).to have_attributes(
      weather_city: I18n.t('custom_coordinates'),
      latitude: BigDecimal('52.1'),
      longitude: BigDecimal('36.2'),
      weather_data: nil
    )
    expect(session.reload.state).to be_nil
    expect(api.sent_messages.last[:text]).to eq(I18n.t('event_created_weather_failed'))
    expect(weather_request).to have_been_requested.once
  end

  it 'rejects an out-of-range longitude without calling WeatherAPI' do
    session = creation_session(state: 'enter_weather_longitude')
    session.new_event = session.new_event.merge('latitude' => 52.1)
    session.save!

    router.call(text_message('180.1'))

    expect(session.reload.state).to eq('enter_weather_longitude')
    expect(session.new_event).not_to have_key('longitude')
    expect(Event.count).to eq(0)
    expect(api.sent_messages.last[:text]).to eq(I18n.t('invalid_longitude'))
    expect(a_request(:any, /weatherapi/)).not_to have_been_made
  end

  it 'does not call WeatherAPI for a stale foreign edit session' do
    author = create_user(telegram_id: 202)
    event = create_event(author: author)
    session = Session.load(telegram_author.id.to_s)
    session.state = 'enter_weather_longitude'
    session.edit_event_id = event.id
    session.new_event = { 'latitude' => 52.1 }
    session.save!
    weather_request = stub_weather_failure('52.1,36.2')

    router.call(text_message('36.2'))

    expect(weather_request).not_to have_been_requested
    expect(event.reload).to have_attributes(weather_city: nil, latitude: nil, longitude: nil)
    expect(session.reload.state).to eq('enter_weather_longitude')
    expect(api.sent_messages.last[:text]).to eq(I18n.t('not_author'))
  end

  it 'updates an authorized event with custom coordinates when the forecast is unavailable' do
    author = create_user(telegram_id: telegram_author.id)
    event = create_event(author: author)
    session = Session.load(telegram_author.id.to_s)
    session.state = 'enter_weather_longitude'
    session.edit_event_id = event.id
    session.new_event = { 'latitude' => 52.1 }
    session.save!
    weather_request = stub_weather_failure('52.1,36.2')

    router.call(text_message('36.2'))

    expect(event.reload).to have_attributes(
      weather_city: I18n.t('custom_coordinates'),
      latitude: BigDecimal('52.1'),
      longitude: BigDecimal('36.2'),
      weather_data: {}
    )
    expect(session.reload.state).to be_nil
    expect(api.sent_messages.last).to include(
      chat_id: private_chat.id,
      text: Bot::Helpers::Formatter.event_info(event),
      parse_mode: 'HTML'
    )
    expect(weather_request).to have_been_requested.once
  end

  it 'moves an authorized event through weather-city and custom-coordinate callbacks' do
    author = create_user(telegram_id: telegram_author.id)
    event = create_event(author: author)

    router.call(callback("change_weather_city-#{event.id}"))
    session = Session.find_by!(user_id: telegram_author.id.to_s)
    expect(session).to have_attributes(state: 'choose_weather_city', edit_event_id: event.id)

    router.call(callback("custom_weather_coords-#{event.id}", id: 'callback-2'))
    expect(session.reload).to have_attributes(state: 'enter_weather_latitude', edit_event_id: event.id)
    expect(api.sent_messages.last[:text]).to eq(I18n.t('enter_weather_latitude'))
  end

  it 'updates an edited event for text choice 1 without creating from stale session data' do
    author = create_user(telegram_id: telegram_author.id)
    event = create_event(author: author, weather_city: 'Старый город')
    session = Session.load(telegram_author.id.to_s)
    session.state = 'choose_weather_city'
    session.edit_event_id = event.id
    session.new_event = {
      'author_id' => author.id,
      'date' => '2026-08-27',
      'time' => '14:00',
      'type' => '🚴‍♀️ Велосипед',
      'location' => 'Старые данные создания'
    }
    session.save!
    weather_request = stub_weather_failure(APP_CONFIG.default_weather_coordinates)

    expect do
      router.call(text_message('1'))
    end.not_to change(Event, :count)

    latitude, longitude = APP_CONFIG.default_weather_coordinates.split(',').map { |value| BigDecimal(value) }
    expect(event.reload).to have_attributes(
      weather_city: APP_CONFIG.default_weather_city,
      latitude: latitude,
      longitude: longitude,
      weather_data: {}
    )
    expect(session.reload).to have_attributes(state: nil, edit_event_id: nil)
    expect(weather_request).to have_been_requested.once
  end

  it 'updates the default weather location even when the forecast is unavailable' do
    author = create_user(telegram_id: telegram_author.id)
    event = create_event(author: author)
    weather_request = stub_weather_failure(APP_CONFIG.default_weather_coordinates)

    router.call(callback("default_weather_city-#{event.id}"))

    latitude, longitude = APP_CONFIG.default_weather_coordinates.split(',').map { |value| BigDecimal(value) }
    expect(event.reload).to have_attributes(
      weather_city: APP_CONFIG.default_weather_city,
      latitude: latitude,
      longitude: longitude,
      weather_data: {}
    )
    expect(api.callback_answers.last[:text]).to eq('Город обновлен, но прогноз получить не удалось')
    expect(weather_request).to have_been_requested.once
  end

  def creation_session(state:)
    author = create_user(telegram_id: telegram_author.id)
    session = Session.load(telegram_author.id.to_s)
    session.state = state
    session.new_event = {
      'author_id' => author.id,
      'date' => '2026-08-26',
      'time' => '13:00',
      'type' => '🚴‍♀️ Велосипед',
      'location' => 'Орёл'
    }
    session.save!
    session
  end

  def text_message(text)
    telegram_message(from: telegram_author, chat: private_chat, text: text)
  end

  def callback(data, id: 'callback-1')
    telegram_callback(from: telegram_author, message: callback_message, data: data, id: id)
  end

  def stub_weather_failure(coordinates)
    stub_request(:get, 'https://api.weatherapi.com/v1/forecast.json')
      .with(query: hash_including('key' => 'test-weather-key', 'q' => coordinates.delete(' ')))
      .to_return(status: 404, body: '{"error":"not found"}')
  end

  def stub_weather_success(coordinates)
    stub_request(:get, 'https://api.weatherapi.com/v1/forecast.json')
      .with(query: hash_including('key' => 'test-weather-key', 'q' => coordinates.delete(' ')))
      .to_return(
        status: 200,
        headers: { 'Content-Type' => 'application/json' },
        body: JSON.generate(
          'forecast' => {
            'forecastday' => [
              {
                'date' => '2026-08-26',
                'hour' => [
                  {
                    'time' => '2026-08-26 13:00',
                    'temp_c' => 18,
                    'feelslike_c' => 17,
                    'condition' => { 'text' => 'Ясно', 'icon' => '//icon' },
                    'wind_kph' => 8,
                    'wind_dir' => 'W',
                    'precip_mm' => 0,
                    'chance_of_rain' => 10,
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
      )
  end
end
