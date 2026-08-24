require 'integration_helper'
require 'tmpdir'
require_relative '../../../app/bot/update_router'

RSpec.describe Bot::Helpers::WeatherScheduler do
  around do |example|
    Dir.mktmpdir('velo-utro-weather-scheduler-spec') do |directory|
      @temp_directory = directory
      example.run
    end
  end

  before do
    described_class.stop
    described_class.instance_variable_set(:@bot, nil)
    stub_const("#{described_class}::LOCK_FILE_PATH", File.join(@temp_directory, 'weather-scheduler.lock'))
    use_app_config(
      'WEATHER_ENABLED' => true,
      'WEATHER_API_KEY' => 'test-weather-key',
      'PUBLIC_CHANNEL_ID' => '@veloutro'
    )
    AppClock.source = -> { Time.utc(2026, 8, 22, 9, 0) }
  end

  after do
    described_class.stop
    described_class.instance_variable_set(:@bot, nil)
  end

  it 'does not report a past event as scheduled' do
    author = create_user(telegram_id: 1)
    past_event = create_event(
      author: author,
      date: Date.new(2026, 8, 22),
      time: '11:00',
      published: true,
      weather_data: { 'temp_c' => 15 }
    )
    bot, = recording_bot
    described_class.start(bot)

    expect(described_class.schedule_weather_updates(past_event)).to be(false)
    expect(described_class.status[:jobs_count]).to eq(0)
  end

  it 'returns false when every weather update offset has already passed' do
    author = create_user(telegram_id: 1)
    imminent_event = create_event(
      author: author,
      date: Date.new(2026, 8, 22),
      time: '13:00',
      published: true,
      weather_data: { 'temp_c' => 15 }
    )
    bot, = recording_bot
    described_class.start(bot)

    expect(described_class.schedule_weather_updates(imminent_event)).to be(false)
    expect(described_class.status[:jobs_count]).to eq(0)
  end

  it 'restores a recently missed weather stage after restart' do
    AppClock.source = -> { Time.zone.local(2026, 8, 26, 11, 30) }
    author = create_user(telegram_id: 1)
    event = create_event(
      author: author,
      date: Date.new(2026, 8, 26),
      time: '13:00',
      published: true,
      weather_data: { 'temp_c' => 15 }
    )
    bot, = recording_bot

    expect(described_class.start(bot)).to be(true)
    expect(described_class.status).to include(jobs_count: 1, event_ids: [event.id])
    expect(described_class.instance_variable_get(:@jobs)).to have_key([event.id, '2h'])
  end

  it 'restores future jobs, replaces them without duplicates, and cancels them' do
    author = create_user(telegram_id: 1)
    event = create_event(
      author: author,
      date: Date.new(2026, 8, 26),
      time: '13:00',
      published: true,
      weather_data: { 'temp_c' => 15 }
    )
    bot, = recording_bot

    expect(described_class.start(bot)).to be(true)
    expect(described_class.status).to include(
      scheduler_running: true,
      jobs_count: 3,
      event_ids: [event.id],
      lock_held: true
    )

    expect(described_class.schedule_weather_updates(event)).to be(true)
    expect(described_class.status[:jobs_count]).to eq(3)

    expect(described_class.cancel_for(event.id)).to eq(3)
    expect(described_class.status[:jobs_count]).to eq(0)
  end

  it 'refuses to start without a Telegram bot' do
    expect(described_class.start).to be(false)
    expect(described_class.status).to include(scheduler_running: false, lock_held: false)
  end

  it 'does not start or acquire a lock when weather is disabled' do
    use_app_config('WEATHER_ENABLED' => false)
    bot, = recording_bot

    expect(described_class.start(bot)).to be(false)
    expect(described_class.status).to include(
      scheduler_running: false,
      jobs_count: 0,
      lock_held: false
    )
    expect(File).not_to exist(described_class::LOCK_FILE_PATH)
  end

  it 'drains an existing outbox even when new weather updates are disabled' do
    use_app_config('WEATHER_ENABLED' => false)
    author = create_user(telegram_id: 1)
    event = create_event(author: author, published: true)
    NotificationDelivery.create!(
      event: event,
      recipient: author,
      notification_type: 'weather.critical_24h',
      context_key: Bot::Helpers::WeatherNotifier.context_key(event),
      idempotency_key: "weather:#{event.id}:disabled-recovery:user:#{author.id}",
      chat_id: author.telegram_id,
      payload: { text: 'Stored weather alert', parse_mode: 'HTML' },
      status: 'pending',
      attempts: 1,
      next_attempt_at: AppClock.now
    )
    bot, api = recording_bot

    expect(described_class.start(bot)).to be(true)

    expect(api.sent_messages).to contain_exactly(
      chat_id: author.telegram_id,
      text: 'Stored weather alert',
      parse_mode: 'HTML'
    )
    expect(described_class.status).to include(
      jobs_count: 0,
      outbox_counts: include(delivered: 1, pending: 0)
    )
  end

  it 'reconciles an unfinalized delivered stage when weather updates are disabled' do
    use_app_config('WEATHER_ENABLED' => false)
    author = create_user(telegram_id: 1)
    event = create_event(author: author, published: true)
    delivery = NotificationDelivery.create!(
      event: event,
      recipient: author,
      notification_type: 'weather.critical_24h',
      context_key: Bot::Helpers::WeatherNotifier.context_key(event),
      idempotency_key: "weather:#{event.id}:disabled-finalization:user:#{author.id}",
      chat_id: author.telegram_id,
      payload: { text: 'Already delivered weather alert', parse_mode: 'HTML' },
      status: 'delivered',
      attempts: 1,
      delivered_at: AppClock.now
    )
    bot, api = recording_bot

    expect(described_class.start(bot)).to be(true)

    expect(api.sent_messages).to be_empty
    expect(event.reload.weather_alerts_sent).to have_key('critical_24h')
    expect(delivery.reload.finalized_at).to eq(AppClock.now)
  end

  it 'does not start while another process holds the scheduler lock' do
    competing_lock = File.open(described_class::LOCK_FILE_PATH, File::RDWR | File::CREAT, 0o644)
    competing_lock.flock(File::LOCK_EX | File::LOCK_NB)
    bot, = recording_bot

    expect(described_class.start(bot)).to be(false)
    expect(described_class.status).to include(scheduler_running: false, lock_held: false)
  ensure
    competing_lock&.flock(File::LOCK_UN)
    competing_lock&.close
  end

  it 'delivers due weather notifications restored from the outbox on startup' do
    AppClock.source = -> { Time.utc(2026, 8, 22, 9, 0) }
    author = create_user(telegram_id: 1)
    event = create_event(author: author, published: true)
    NotificationDelivery.create!(
      event: event,
      recipient: author,
      notification_type: 'weather.critical_24h',
      context_key: Bot::Helpers::WeatherNotifier.context_key(event),
      idempotency_key: "weather:#{event.id}:critical_24h:user:#{author.id}",
      chat_id: author.telegram_id,
      payload: { text: 'Weather changed', parse_mode: 'HTML' },
      status: 'pending',
      attempts: 1,
      next_attempt_at: AppClock.now
    )
    bot, api = recording_bot

    expect(described_class.start(bot)).to be(true)

    expect(api.sent_messages).to contain_exactly(
      chat_id: author.telegram_id,
      text: 'Weather changed',
      parse_mode: 'HTML'
    )
    expect(NotificationDelivery.last).to have_attributes(status: 'delivered', attempts: 2)
    expect(event.reload.weather_alerts_sent).to include('critical_24h' => AppClock.now.to_s)
    expect(described_class.status).to include(outbox_job_active: true)
  end

  it 'does not schedule a draft and starts weather jobs after its first publication' do
    telegram_author = telegram_user(id: 101, first_name: 'Никита', username: 'nixon')
    author = create_user(telegram_id: telegram_author.id)
    event = create_event(
      author: author,
      date: Date.new(2026, 8, 26),
      time: '13:00',
      weather_data: { 'temp_c' => 15 }
    )
    bot, = recording_bot

    expect(described_class.start(bot)).to be(true)
    expect(described_class.status[:jobs_count]).to eq(0)
    expect(described_class.schedule_weather_updates(event)).to be(false)

    callback = telegram_callback(
      from: telegram_author,
      message: telegram_message(
        from: telegram_author,
        chat: telegram_chat(id: telegram_author.id),
        text: 'Event',
        message_id: 55
      ),
      data: "publish-#{event.id}"
    )
    Bot::UpdateRouter.new(bot).call(callback)

    expect(event.reload).to be_published
    expect(described_class.status[:jobs_count]).to eq(3)

    event.update!(published: false)
    expect(described_class.schedule_weather_updates(event)).to be(false)
    expect(described_class.status[:jobs_count]).to eq(0)
  end

  it 'cancels stale jobs and skips updates after an event is moved into the past' do
    author = create_user(telegram_id: 1)
    event = create_event(
      author: author,
      date: Date.new(2026, 8, 26),
      time: '13:00',
      published: true,
      latitude: 52.1,
      longitude: 36.2,
      weather_data: { 'temp_c' => 15 }
    )
    bot, = recording_bot
    described_class.start(bot)
    expect(described_class.status[:jobs_count]).to eq(3)

    event.update!(date: Date.new(2026, 8, 22), time: '08:00')

    expect(described_class.schedule_weather_updates(event)).to be(false)
    expect(described_class.status[:jobs_count]).to eq(0)

    described_class.send(:run_update, event.id, '24h')
    expect(a_request(:get, /weatherapi/)).not_to have_been_made
  end

  it 'skips a stale job after an event is moved to another future date' do
    author = create_user(telegram_id: 1)
    event = create_event(
      author: author,
      date: Date.new(2026, 8, 26),
      time: '13:00',
      published: true,
      latitude: 52.1,
      longitude: 36.2,
      weather_data: { 'temp_c' => 15 }
    )
    bot, = recording_bot
    described_class.start(bot)
    stale_starts_at = event.starts_at
    weather_request = stub_request(:get, 'https://api.weatherapi.com/v1/forecast.json')
                      .with(query: hash_including('key' => 'test-weather-key'))
                      .to_return(status: 200, body: weather_response.to_json)

    event.update!(date: Date.new(2026, 8, 27))
    expect(described_class.schedule_weather_updates(event)).to be(true)

    described_class.send(:run_update, event.id, '24h', stale_starts_at)

    expect(weather_request).not_to have_been_requested
  end

  it 'skips a replaced job when the event start time has not changed' do
    author = create_user(telegram_id: 1)
    event = create_event(
      author: author,
      date: Date.new(2026, 8, 26),
      time: '13:00',
      published: true,
      latitude: 52.1,
      longitude: 36.2,
      weather_data: { 'temp_c' => 15 }
    )
    bot, = recording_bot
    described_class.start(bot)
    stale_job = described_class.instance_variable_get(:@jobs).fetch([event.id, '24h'])
    weather_request = stub_request(:get, 'https://api.weatherapi.com/v1/forecast.json')
                      .with(query: hash_including('key' => 'test-weather-key'))
                      .to_return(status: 200, body: weather_response.to_json)

    expect(described_class.schedule_weather_updates(event)).to be(true)

    described_class.send(:run_update, event.id, '24h', event.starts_at, stale_job)

    expect(weather_request).not_to have_been_requested
  end

  it 'does not request weather for an event deleted before its job runs' do
    author = create_user(telegram_id: 1)
    event = create_event(
      author: author,
      date: Date.new(2026, 8, 26),
      time: '13:00',
      published: true,
      weather_data: { 'temp_c' => 15 }
    )
    event_id = event.id
    bot, = recording_bot
    described_class.start(bot)
    event.destroy!

    described_class.send(:run_update, event_id, '24h')

    expect(a_request(:get, /weatherapi/)).not_to have_been_made
  end

  it 'delivers a critical three-day update through the scheduler' do
    author = create_user(telegram_id: 1)
    participant = create_user(telegram_id: 2)
    event = create_event(
      author: author,
      date: Date.new(2026, 8, 26),
      time: '13:00',
      published: true,
      latitude: 52.1,
      longitude: 36.2,
      weather_data: weather_snapshot(temp: 10)
    )
    event.participants << participant
    weather_request = stub_request(:get, 'https://api.weatherapi.com/v1/forecast.json')
                      .with(query: hash_including('key' => 'test-weather-key'))
                      .to_return(status: 200, body: weather_response.to_json)
    bot, api = recording_bot
    described_class.start(bot)

    described_class.send(:run_update, event.id, '3d')

    expect(weather_request).to have_been_requested.once
    expect(api.sent_messages.map { |message| message[:chat_id] }).to contain_exactly('1', '2')
    expect(event.reload.weather_alerts_sent).to have_key('critical_3d')
  end

  it 'rolls back weather changes when the matching notification cannot enter the outbox' do
    AppClock.source = -> { Time.zone.local(2026, 8, 25, 9, 0) }
    author = create_user(telegram_id: 1)
    event = create_event(
      author: author,
      date: Date.new(2026, 8, 26),
      time: '13:00',
      published: true,
      latitude: 52.1,
      longitude: 36.2,
      weather_data: weather_snapshot(temp: 10)
    )
    stub_request(:get, 'https://api.weatherapi.com/v1/forecast.json')
      .with(query: hash_including('key' => 'test-weather-key'))
      .to_return(status: 200, body: weather_response.to_json)
    allow(Notifications::Outbox).to receive(:enqueue!)
      .and_raise(ActiveRecord::StatementInvalid, 'outbox unavailable')
    bot, api = recording_bot
    described_class.start(bot)

    jobs = described_class.instance_variable_get(:@jobs)
    original_job = jobs.fetch([event.id, '24h'])

    described_class.send(:run_update, event.id, '24h', event.starts_at, original_job)

    expect(event.reload.weather_data).to eq(weather_snapshot(temp: 10))
    expect(event.weather_history).to be_empty
    expect(api.sent_messages).to be_empty
    expect(jobs.fetch([event.id, '24h'])).not_to equal(original_job)
  end

  it 'retries the weather stage when neither WeatherAPI nor stored history has data' do
    AppClock.source = -> { Time.zone.local(2026, 8, 25, 9, 0) }
    author = create_user(telegram_id: 1)
    event = create_event(
      author: author,
      date: Date.new(2026, 8, 26),
      time: '13:00',
      published: true,
      latitude: 52.1,
      longitude: 36.2,
      weather_data: weather_snapshot(temp: 10)
    )
    stub_request(:get, 'https://api.weatherapi.com/v1/forecast.json')
      .with(query: hash_including('key' => 'test-weather-key'))
      .to_return(status: 404, body: '{"error":"not found"}')
    bot, = recording_bot
    described_class.start(bot)
    jobs = described_class.instance_variable_get(:@jobs)
    original_job = jobs.fetch([event.id, '24h'])

    described_class.send(:run_update, event.id, '24h', event.starts_at, original_job)

    expect(event.reload.weather_data).to eq(weather_snapshot(temp: 10))
    expect(jobs.fetch([event.id, '24h'])).not_to equal(original_job)
  end

  it 'stops retrying a weather stage after the configured attempt limit' do
    AppClock.source = -> { Time.zone.local(2026, 8, 25, 9, 0) }
    author = create_user(telegram_id: 1)
    event = create_event(
      author: author,
      date: Date.new(2026, 8, 26),
      time: '13:00',
      published: true,
      latitude: 52.1,
      longitude: 36.2,
      weather_data: weather_snapshot(temp: 10)
    )
    stub_request(:get, 'https://api.weatherapi.com/v1/forecast.json')
      .with(query: hash_including('key' => 'test-weather-key'))
      .to_return(status: 404, body: '{"error":"not found"}')
    bot, = recording_bot
    described_class.start(bot)
    jobs = described_class.instance_variable_get(:@jobs)
    original_job = jobs.fetch([event.id, '24h'])

    described_class.send(
      :run_update,
      event.id,
      '24h',
      event.starts_at,
      original_job,
      described_class::MAX_UPDATE_RETRIES
    )

    expect(jobs.fetch([event.id, '24h'])).to equal(original_job)
  end

  it 'publishes a two-hour forecast through the scheduler' do
    AppClock.source = -> { Time.utc(2026, 8, 26, 8, 0) }
    author = create_user(telegram_id: 1)
    event = create_event(
      author: author,
      date: Date.new(2026, 8, 26),
      time: '13:00',
      published: true,
      latitude: 52.1,
      longitude: 36.2,
      weather_data: weather_snapshot(temp: 15)
    )
    weather_request = stub_request(:get, 'https://api.weatherapi.com/v1/forecast.json')
                      .with(query: hash_including('key' => 'test-weather-key'))
                      .to_return(status: 200, body: weather_response.to_json)
    bot, api = recording_bot
    described_class.start(bot)

    described_class.send(:run_update, event.id, '2h')

    expect(weather_request).to have_been_requested.once
    expect(api.sent_messages).to contain_exactly(
      include(chat_id: '@veloutro', text: include('Финальный прогноз погоды'))
    )
    expect(event.reload.weather_alerts_sent).to have_key('2h_channel')
  end

  it 'updates persisted weather and notifies users after a critical 24h change' do
    author = create_user(telegram_id: 1)
    participant = create_user(telegram_id: 2)
    event = create_event(
      author: author,
      date: Date.new(2026, 8, 26),
      time: '13:00',
      published: true,
      latitude: 52.1,
      longitude: 36.2,
      weather_data: {
        'temp_c' => 10,
        'feelslike_c' => 10,
        'condition' => 'Облачно',
        'wind_kph' => 5,
        'precip_prob' => 10,
        'alerts' => []
      }
    )
    event.participants << participant
    weather_request = stub_request(:get, 'https://api.weatherapi.com/v1/forecast.json')
                      .with(query: hash_including('key' => 'test-weather-key'))
                      .to_return(
                        status: 200,
                        headers: { 'Content-Type' => 'application/json' },
                        body: weather_response.to_json
                      )
    bot, api = recording_bot
    described_class.start(bot)

    described_class.send(:run_update, event.id, '24h')

    event.reload
    expect(weather_request).to have_been_requested.once
    expect(event.weather_data).to include('temp_c' => 20, 'condition' => 'Ясно')
    expect(event.weather_history.last['weather_data']).to include('temp_c' => 10)
    expect(event.weather_alerts_sent).to include('critical_24h')
    expect(api.sent_messages.map { |message| message[:chat_id] }).to contain_exactly('1', '2')
  end

  it 'uses a fresh stored forecast when WeatherAPI is unavailable' do
    author = create_user(telegram_id: 1)
    current_weather = weather_snapshot(temp: 15)
    fallback_weather = weather_snapshot(temp: 14)
    event = create_event(
      author: author,
      date: Date.new(2026, 8, 26),
      time: '13:00',
      published: true,
      latitude: 52.1,
      longitude: 36.2,
      weather_data: current_weather,
      weather_history: [
        {
          timestamp: (AppClock.now - 1.hour).iso8601,
          weather_data: fallback_weather
        }
      ]
    )
    weather_request = stub_request(:get, 'https://api.weatherapi.com/v1/forecast.json')
                      .with(query: hash_including('key' => 'test-weather-key'))
                      .to_return(status: 404, body: '{"error":"not found"}')
    bot, api = recording_bot
    described_class.start(bot)

    described_class.send(:run_update, event.id, '24h')

    expect(event.reload.weather_data).to include('temp_c' => 14, 'condition' => 'Ясно')
    expect(event.weather_history.last['weather_data']).to include('temp_c' => 15)
    expect(weather_request).to have_been_requested.once
    expect(api.sent_messages).to be_empty
  end

  it 'keeps the current forecast when WeatherAPI and stored history are both stale' do
    author = create_user(telegram_id: 1)
    current_weather = weather_snapshot(temp: 15)
    event = create_event(
      author: author,
      date: Date.new(2026, 8, 26),
      time: '13:00',
      published: true,
      latitude: 52.1,
      longitude: 36.2,
      weather_data: current_weather,
      weather_history: [
        {
          timestamp: (AppClock.now - 48.hours).iso8601,
          weather_data: weather_snapshot(temp: 14)
        }
      ]
    )
    weather_request = stub_request(:get, 'https://api.weatherapi.com/v1/forecast.json')
                      .with(query: hash_including('key' => 'test-weather-key'))
                      .to_return(status: 404, body: '{"error":"not found"}')
    bot, api = recording_bot
    described_class.start(bot)

    described_class.send(:run_update, event.id, '24h')

    expect(event.reload.weather_data).to eq(current_weather)
    expect(event.weather_history.length).to eq(1)
    expect(weather_request).to have_been_requested.once
    expect(api.sent_messages).to be_empty
  end

  def weather_snapshot(temp:)
    {
      'temp_c' => temp,
      'feelslike_c' => temp,
      'condition' => 'Ясно',
      'wind_kph' => 5,
      'precip_prob' => 10,
      'alerts' => []
    }
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
                'temp_c' => 20,
                'feelslike_c' => 20,
                'condition' => { 'text' => 'Ясно', 'icon' => '//icon' },
                'wind_kph' => 5,
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
