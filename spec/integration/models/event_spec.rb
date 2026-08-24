require 'integration_helper'

RSpec.describe Event do
  let(:author) { create_user(telegram_id: 1) }

  describe 'time validation' do
    it 'requires exact HH:MM for new records' do
      event = build_event(author: author, time: '9:00')

      expect(event).not_to be_valid
      expect(event.errors[:time]).not_to be_empty
    end

    it 'keeps an unchanged legacy time readable' do
      event = create_event(author: author, time: '09:00')
      event.update_column(:time, '9:00 - 10:00')
      event.reload

      expect(event).to be_valid
      expect(event.starts_at).to eq(
        ActiveSupport::TimeZone['Europe/Moscow'].local(2026, 8, 23, 9, 0)
      )
    end
  end

  describe '.upcoming' do
    it 'excludes an event that already started today' do
      AppClock.source = -> { Time.utc(2026, 8, 23, 9, 0) }

      past = create_event(author: author, date: Date.new(2026, 8, 23), time: '11:59')
      current = create_event(author: author, date: Date.new(2026, 8, 23), time: '12:00')
      future = create_event(author: author, date: Date.new(2026, 8, 24), time: '09:00')

      expect(described_class.upcoming).to eq([current, future])
      expect(described_class.upcoming).not_to include(past)
    end
  end

  describe '.next_24_hours' do
    it 'returns events from now through the next 24 hours in start order' do
      now = ActiveSupport::TimeZone['Europe/Moscow'].local(2026, 8, 23, 12, 0)

      past = create_event(author: author, date: Date.new(2026, 8, 23), time: '11:59')
      first = create_event(author: author, date: Date.new(2026, 8, 23), time: '12:00')
      last = create_event(author: author, date: Date.new(2026, 8, 24), time: '12:00')
      later = create_event(author: author, date: Date.new(2026, 8, 24), time: '12:01')

      expect(described_class.next_24_hours(now: now)).to eq([first, last])
      expect(described_class.next_24_hours(now: now)).not_to include(past, later)
    end
  end

  describe '#weather_changed_significantly?' do
    let(:event) do
      create_event(
        author: author,
        weather_data: {
          'temp_c' => 15,
          'precip_prob' => 40,
          'wind_kph' => 10,
          'alerts' => []
        }
      )
    end

    it 'treats the first available forecast as significant' do
      event.update!(weather_data: nil)

      expect(event.weather_changed_significantly?('temp_c' => 15)).to be(true)
    end

    it 'treats a temperature change over five degrees as significant' do
      new_weather = event.weather.merge('temp_c' => 20.1)

      expect(event.weather_changed_significantly?(new_weather)).to be(true)
    end

    it 'treats crossing the 50-percent precipitation threshold as significant' do
      new_weather = event.weather.merge('precip_prob' => 51)

      expect(event.weather_changed_significantly?(new_weather)).to be(true)
    end

    it 'treats a wind-speed change over ten kilometres per hour as significant' do
      new_weather = event.weather.merge('wind_kph' => 20.1)

      expect(event.weather_changed_significantly?(new_weather)).to be(true)
    end

    it 'treats a newly appeared weather alert as significant' do
      new_weather = event.weather.merge('alerts' => [{ 'event' => 'Strong wind' }])

      expect(event.weather_changed_significantly?(new_weather)).to be(true)
    end

    it 'does not treat changes exactly at the configured thresholds as significant' do
      new_weather = event.weather.merge(
        'temp_c' => 20,
        'precip_prob' => 50,
        'wind_kph' => 20,
        'alerts' => []
      )

      expect(event.weather_changed_significantly?(new_weather)).to be(false)
    end
  end

  describe '#channel_link' do
    it 'builds a public-channel link from a username' do
      use_app_config('PUBLIC_CHANNEL_ID' => '@veloutro')
      event = create_event(author: author, channel_message_id: 321)

      expect(event.channel_link).to eq('https://t.me/veloutro/321')
    end

    it 'builds a private-channel link from a Telegram numeric identifier' do
      use_app_config('PUBLIC_CHANNEL_ID' => '-1001234567890')
      event = create_event(author: author, channel_message_id: 654)

      expect(event.channel_link).to eq('https://t.me/c/1234567890/654')
    end

    it 'returns nil without a message identifier or for an unsupported channel format' do
      use_app_config('PUBLIC_CHANNEL_ID' => '123456')

      expect(create_event(author: author).channel_link).to be_nil
      expect(create_event(author: author, channel_message_id: 1).channel_link).to be_nil
    end
  end

  def build_event(author:, **attributes)
    Event.new(
      {
        author: author,
        date: Date.new(2026, 8, 23),
        time: '09:00',
        event_type: '🚴‍♀️ Велосипед',
        location: 'Орёл'
      }.merge(attributes)
    )
  end
end
