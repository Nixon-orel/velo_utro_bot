require 'integration_helper'
require_relative '../../../app/services/event_weather_service'

RSpec.describe EventWeatherService do
  before do
    use_app_config(
      'WEATHER_API_KEY' => 'test-weather-key',
      'WEATHER_ENABLED' => false
    )
  end

  it 'creates exactly one event with normalized weather data' do
    session = creation_session
    weather_request = stub_request(:get, 'https://api.weatherapi.com/v1/forecast.json')
                      .with(query: hash_including('key' => 'test-weather-key', 'q' => '52.1,36.2'))
                      .to_return(
                        status: 200,
                        headers: { 'Content-Type' => 'application/json' },
                        body: weather_response.to_json
                      )
    result = nil

    expect do
      result = described_class.create_event_with_weather(session, '52.1,36.2', 'Орёл')
    end.to change(Event, :count).by(1)

    expect(result).to be_success
    expect(result.metadata[:weather_available]).to be(true)
    expect(result.value).to have_attributes(
      weather_city: 'Орёл',
      latitude: BigDecimal('52.1'),
      longitude: BigDecimal('36.2')
    )
    expect(result.value.weather_data).to include('temp_c' => 18, 'condition' => 'Ясно')
    expect(weather_request).to have_been_requested.once
  end

  it 'creates one event without weather when WeatherAPI is unavailable' do
    session = creation_session
    weather_request = stub_request(:get, 'https://api.weatherapi.com/v1/forecast.json')
                      .with(query: hash_including('key' => 'test-weather-key', 'q' => '52.1,36.2'))
                      .to_return(status: 404, body: '{"error":"not found"}')
    result = nil

    expect do
      result = described_class.create_event_with_weather(session, '52.1,36.2', 'Орёл')
    end.to change(Event, :count).by(1)

    expect(result).to be_success
    expect(result.metadata[:weather_available]).to be(false)
    expect(result.value.weather_data).to be_nil
    expect(result.value).to have_attributes(
      weather_city: 'Орёл',
      latitude: BigDecimal('52.1'),
      longitude: BigDecimal('36.2')
    )
    expect(weather_request).to have_been_requested.once
  end

  it 'does not persist an event when session attributes are invalid' do
    session = creation_session
    session.new_event = session.new_event.merge('time' => '9:00')
    session.save!
    stub_request(:get, 'https://api.weatherapi.com/v1/forecast.json')
      .with(query: hash_including('key' => 'test-weather-key', 'q' => '52.1,36.2'))
      .to_return(
        status: 200,
        headers: { 'Content-Type' => 'application/json' },
        body: weather_response.to_json
      )

    expect do
      result = described_class.create_event_with_weather(session, '52.1,36.2', 'Орёл')
      expect(result.error_code).to eq(:validation_failed)
    end.not_to change(Event, :count)
  end

  it 'rejects an invalid event date before calling WeatherAPI' do
    session = creation_session
    session.new_event = session.new_event.merge('date' => 'not-a-date')
    session.save!
    weather_request = stub_weather_failure

    expect do
      result = described_class.create_event_with_weather(session, '52.1,36.2', 'Орёл')
      expect(result.error_code).to eq(:invalid_date)
    end.not_to change(Event, :count)

    expect(weather_request).not_to have_been_requested
  end

  it 'does not call WeatherAPI for an already consumed creation state' do
    session = creation_session(state: nil)
    weather_request = stub_weather_failure

    result = described_class.create_event_with_weather(
      session,
      '52.1,36.2',
      'Орёл',
      expected_state: 'enter_additional_info'
    )

    expect(result).to be_failure
    expect(result.error_code).to eq(:already_processed)
    expect(weather_request).not_to have_been_requested
    expect(Event.count).to eq(0)
  end

  it 'does not call WeatherAPI while another fresh creation claim is active' do
    now = Time.zone.local(2026, 8, 23, 12, 0)
    AppClock.source = -> { now }
    session = creation_session(
      state: 'enter_additional_info',
      creation_claim: { 'token' => 'other-worker', 'claimed_at' => now.to_f }
    )
    weather_request = stub_weather_failure

    result = described_class.create_event_with_weather(
      session,
      '52.1,36.2',
      'Орёл',
      expected_state: 'enter_additional_info'
    )

    expect(result).to be_failure
    expect(result.error_code).to eq(:already_processing)
    expect(weather_request).not_to have_been_requested
    expect(Event.count).to eq(0)
  end

  it 'recovers an expired creation claim' do
    now = Time.zone.local(2026, 8, 23, 12, 0)
    AppClock.source = -> { now }
    session = creation_session(
      state: 'enter_additional_info',
      creation_claim: { 'token' => 'crashed-worker', 'claimed_at' => now.to_f - 3600 }
    )
    weather_request = stub_weather_failure

    result = described_class.create_event_with_weather(
      session,
      '52.1,36.2',
      'Орёл',
      expected_state: 'enter_additional_info'
    )

    expect(result).to be_success
    expect(weather_request).to have_been_requested.once
    expect(Event.count).to eq(1)
    expect(session.reload.state).to be_nil
  end

  it 'makes one WeatherAPI request when two final messages race', :concurrent do
    session = creation_session(state: 'enter_additional_info')
    weather_request = stub_weather_failure
    gate = Queue.new
    ready = Queue.new
    results = Queue.new
    errors = Queue.new

    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          gate.pop
          results << described_class.create_event_with_weather(
            Session.find(session.id),
            '52.1,36.2',
            'Орёл',
            expected_state: 'enter_additional_info'
          )
        end
      rescue => e
        errors << e
      end
    end

    begin
      threads.count.times { queue_pop(ready) }
    ensure
      threads.count.times { gate << true }
      join_threads(threads)
    end

    raise errors.pop unless errors.empty?

    creation_results = threads.count.times.map { queue_pop(results) }
    expect(creation_results.count(&:success?)).to eq(1)
    failed_result = creation_results.find(&:failure?)
    expect(%i[already_processing already_processed]).to include(failed_result.error_code)
    expect(Event.count).to eq(1)
    expect(weather_request).to have_been_requested.once
  end

  it 'rejects weather editing by another user before calling WeatherAPI' do
    author = create_user(telegram_id: 10)
    stranger = create_user(telegram_id: 20)
    event = create_event(author: author)
    weather_request = stub_weather_failure

    result = described_class.update_event_weather(
      event: event,
      actor: stranger,
      coordinates: '52.1,36.2',
      city_name: 'Орёл'
    )

    expect(result.error_code).to eq(:forbidden)
    expect(event.reload).to have_attributes(weather_city: nil, latitude: nil, longitude: nil)
    expect(weather_request).not_to have_been_requested
  end

  it 'updates an authored event with normalized WeatherAPI data' do
    author = create_user(telegram_id: 10)
    event = create_event(
      author: author,
      date: Date.new(2026, 8, 26),
      time: '13:00'
    )
    weather_request = stub_request(:get, 'https://api.weatherapi.com/v1/forecast.json')
                      .with(query: hash_including('key' => 'test-weather-key', 'q' => '52.1,36.2'))
                      .to_return(
                        status: 200,
                        headers: { 'Content-Type' => 'application/json' },
                        body: weather_response.to_json
                      )

    result = described_class.update_event_weather(
      event: event,
      actor: author,
      coordinates: '52.1,36.2',
      city_name: 'Орёл'
    )

    expect(result).to be_success
    expect(result.metadata[:weather_available]).to be(true)
    expect(event.reload).to have_attributes(
      weather_city: 'Орёл',
      latitude: BigDecimal('52.1'),
      longitude: BigDecimal('36.2')
    )
    expect(event.weather_data).to include('temp_c' => 18, 'condition' => 'Ясно')
    expect(weather_request).to have_been_requested.once
  end

  def creation_session(state: nil, creation_claim: nil)
    author = create_user(telegram_id: 1)
    data = {
      'state' => state,
      'new_event' => {
        'author_id' => author.id,
        'date' => '2026-08-26',
        'time' => '13:00',
        'type' => '🚴‍♀️ Велосипед',
        'location' => 'Орёл',
        'distance' => '25 км'
      }
    }
    data['creation_claim'] = creation_claim if creation_claim

    Session.create!(
      user_id: author.telegram_id,
      data: data
    )
  end

  def stub_weather_failure
    stub_request(:get, 'https://api.weatherapi.com/v1/forecast.json')
      .with(query: hash_including('key' => 'test-weather-key', 'q' => '52.1,36.2'))
      .to_return(status: 404, body: '{"error":"not found"}')
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
