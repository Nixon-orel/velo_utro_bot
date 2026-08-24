require 'integration_helper'
require_relative '../../../app/bot/update_router'

RSpec.describe 'Telegram event creation flows' do
  let(:bot_and_api) { recording_bot }
  let(:bot) { bot_and_api.first }
  let(:api) { bot_and_api.last }
  let(:router) { Bot::UpdateRouter.new(bot) }
  let(:telegram_author) { telegram_user(id: 101, first_name: 'Никита', username: 'nixon') }
  let(:private_chat) { telegram_chat(id: telegram_author.id) }
  let(:callback_message) do
    telegram_message(from: telegram_author, chat: private_chat, text: 'Choice', message_id: 55)
  end

  before do
    AppClock.source = -> { Time.zone.local(2026, 8, 23, 12, 0) }
    use_app_config('WEATHER_ENABLED' => false)
  end

  it 'creates a static event without asking for active-event fields' do
    expect do
      send_text('/create')
      choose('calendar_day_2026-08-24')
      send_text('19:30')
      choose('🎲 Настолки')
      send_text('Клуб «Фишка»')

      expect(current_session.state).to eq('enter_additional_info')
      send_text('-')
    end.to change(Event, :count).by(1)

    event = Event.order(:id).last
    expect(event).to have_attributes(
      date: Date.new(2026, 8, 24),
      time: '19:30',
      event_type: '🎲 Настолки',
      location: 'Клуб «Фишка»',
      distance: nil,
      pace: nil,
      track: nil,
      map: nil,
      additional_info: nil
    )
    expect(event.author.telegram_id).to eq(telegram_author.id.to_s)
    expect(current_session.state).to be_nil
    expect(api.sent_messages.last[:text]).to eq(I18n.t('event_created'))
    expect(publish_callback_for_last_message).to eq("publish-#{event.id}")
  end

  it 'creates an active event through every persisted state exactly once' do
    final_message = nil

    expect do
      send_text('/create')
      choose('calendar_day_2026-08-25')
      send_text('08:15')
      choose('🚴‍♀️ Велосипед')
      send_text('Парк Победы')
      send_text('42 км')
      send_text('20–25 км/ч')
      send_text('-')
      send_text('https://example.test/route-map')
      final_message = send_text('Берите фонари')
      router.call(final_message)
    end.to change(Event, :count).by(1)

    event = Event.order(:id).last
    expect(event).to have_attributes(
      date: Date.new(2026, 8, 25),
      time: '08:15',
      event_type: '🚴‍♀️ Велосипед',
      location: 'Парк Победы',
      distance: '42 км',
      pace: '20–25 км/ч',
      track: nil,
      map: 'https://example.test/route-map',
      additional_info: 'Берите фонари'
    )
    expect(current_session.state).to be_nil
    expect(api.sent_messages[-2][:text]).to eq(I18n.t('event_created'))
    expect(api.sent_messages.last[:text]).to eq(I18n.t('unknown_command'))
    expect(publish_callback_for_message(api.sent_messages[-2])).to eq("publish-#{event.id}")
  end

  it 'creates one event when two final messages are processed concurrently', :concurrent do
    author = create_user(telegram_id: telegram_author.id, username: telegram_author.first_name)
    session = Session.load(telegram_author.id.to_s)
    session.state = 'enter_additional_info'
    session.new_event = {
      'author_id' => author.id,
      'date' => '2026-08-25',
      'time' => '08:15',
      'type' => '🚴‍♀️ Велосипед',
      'location' => 'Парк Победы'
    }
    session.save!
    message = telegram_message(from: telegram_author, chat: private_chat, text: 'Берите фонари')
    entered = Queue.new
    release = Queue.new
    errors = Queue.new
    original_process = Bot::States.method(:process)

    allow(Bot::States).to receive(:process) do |state, *arguments|
      entered << true
      queue_pop(release)
      original_process.call(state, *arguments)
    end

    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          router.call(message)
        end
      rescue => e
        errors << e
      end
    end

    begin
      threads.count.times { queue_pop(entered) }
    ensure
      threads.count.times { release << true }
      join_threads(threads)
    end

    raise errors.pop unless errors.empty?

    expect(Event.count).to eq(1)
    expect(session.reload.state).to be_nil
  end

  it 'finishes creation with a default-city forecast when weather is enabled' do
    use_app_config(
      'WEATHER_ENABLED' => true,
      'WEATHER_API_KEY' => 'test-weather-key'
    )
    session = prepared_creation_session
    weather_request = stub_request(:get, 'https://api.weatherapi.com/v1/forecast.json')
                      .with(
                        query: hash_including(
                          'key' => 'test-weather-key',
                          'q' => APP_CONFIG.default_weather_coordinates.delete(' ')
                        )
                      )
                      .to_return(
                        status: 200,
                        headers: { 'Content-Type' => 'application/json' },
                        body: weather_response.to_json
                      )

    expect do
      send_text('Берите фонари')
    end.to change(Event, :count).by(1)

    event = Event.order(:id).last
    callbacks = api.sent_messages.last[:reply_markup].inline_keyboard.flatten.map(&:callback_data)
    expect(event.weather_data).to include('temp_c' => 18, 'condition' => 'Ясно')
    expect(event).to have_attributes(weather_city: APP_CONFIG.default_weather_city)
    expect(session.reload.state).to be_nil
    expect(api.sent_messages.last[:text]).to include('Мероприятие успешно создано', 'Ясно, 18°C')
    expect(callbacks).to eq(["publish-#{event.id}", "change_weather_city-#{event.id}"])
    expect(weather_request).to have_been_requested.once
  end

  it 'finishes creation without a forecast when WeatherAPI is unavailable' do
    use_app_config(
      'WEATHER_ENABLED' => true,
      'WEATHER_API_KEY' => 'test-weather-key'
    )
    session = prepared_creation_session
    weather_request = stub_request(:get, 'https://api.weatherapi.com/v1/forecast.json')
                      .with(
                        query: hash_including(
                          'key' => 'test-weather-key',
                          'q' => APP_CONFIG.default_weather_coordinates.delete(' ')
                        )
                      )
                      .to_return(status: 404, body: '{"error":"not found"}')

    expect do
      send_text('-')
    end.to change(Event, :count).by(1)

    event = Event.order(:id).last
    callbacks = api.sent_messages.last[:reply_markup].inline_keyboard.flatten.map(&:callback_data)
    expect(event.weather_data).to be_nil
    expect(event).to have_attributes(weather_city: APP_CONFIG.default_weather_city)
    expect(session.reload.state).to be_nil
    expect(api.sent_messages.last[:text]).to eq(I18n.t('event_created_weather_failed'))
    expect(callbacks).to eq(["publish-#{event.id}", "change_weather_city-#{event.id}"])
    expect(weather_request).to have_been_requested.once
  end

  it 'invalidates an unfinished creation claim when create is restarted' do
    author = create_user(telegram_id: telegram_author.id, username: telegram_author.first_name)
    session = Session.load(telegram_author.id.to_s)
    session.state = 'enter_additional_info'
    session.new_event = {
      'author_id' => author.id,
      'date' => '2026-08-25',
      'time' => '08:15',
      'type' => '🚴‍♀️ Велосипед',
      'location' => 'Старое событие'
    }
    session['creation_claim'] = {
      'token' => 'stale-worker',
      'claimed_at' => AppClock.now.to_f
    }
    session.save!

    send_text('/create')

    session.reload
    expect(session.state).to eq('choose_date')
    expect(session.new_event).to eq('author_id' => author.id)
    expect(session['creation_claim']).to be_nil
  end

  private

  def send_text(text)
    message = telegram_message(from: telegram_author, chat: private_chat, text: text)
    router.call(message)
    message
  end

  def choose(data)
    router.call(telegram_callback(from: telegram_author, message: callback_message, data: data))
  end

  def current_session
    Session.find_by!(user_id: telegram_author.id.to_s).reload
  end

  def publish_callback_for_last_message
    publish_callback_for_message(api.sent_messages.last)
  end

  def publish_callback_for_message(payload)
    payload[:reply_markup].inline_keyboard.dig(0, 0).callback_data
  end

  def prepared_creation_session
    author = create_user(telegram_id: telegram_author.id, username: telegram_author.first_name)
    session = Session.load(telegram_author.id.to_s)
    session.state = 'enter_additional_info'
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

  def weather_response
    {
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
    }
  end
end
