require 'integration_helper'
require_relative '../../../app/services/weather_service'

RSpec.describe WeatherService do
  RecordingNotifier = Struct.new(:alerts) do
    def initialize
      super([])
    end

    def send_alert(level, message, data)
      alerts << [level, message, data]
    end
  end

  after do
    described_class.admin_notifier = nil
  end

  describe '.get_fallback_weather' do
    let(:now) { Time.zone.local(2026, 8, 24, 12, 0) }
    let(:event) { create_event(author: create_user(telegram_id: 501)) }

    before do
      AppClock.source = -> { now }
    end

    it 'returns normalized data from the latest fresh history entry' do
      event.update!(
        weather_history: [
          {
            timestamp: (now - 3.hours).iso8601,
            weather_data: { temp_c: 12, alerts: [{ event: 'Wind' }] }
          },
          {
            timestamp: (now - 1.hour).iso8601,
            weather_data: { temp_c: 18, nested: { source: 'history' } }
          }
        ]
      )

      expect(described_class.get_fallback_weather(event.reload)).to eq(
        'temp_c' => 18,
        'nested' => { 'source' => 'history' }
      )
    end

    it 'supports the legacy updated_at and data history keys' do
      event.update!(
        weather_history: [
          {
            updated_at: (now - 2.hours).iso8601,
            data: { condition: 'Ясно', temp_c: 17 }
          }
        ]
      )

      expect(described_class.get_fallback_weather(event.reload)).to eq(
        'condition' => 'Ясно',
        'temp_c' => 17
      )
    end

    it 'does not use history that is exactly 48 hours old' do
      event.update!(
        weather_history: [
          {
            timestamp: (now - 48.hours).iso8601,
            weather_data: { temp_c: 10 }
          }
        ]
      )

      expect(described_class.get_fallback_weather(event.reload)).to be_nil
    end

    it 'does not use an incomplete history entry' do
      event.update!(weather_history: [{ timestamp: (now - 1.hour).iso8601 }])

      expect(described_class.get_fallback_weather(event.reload)).to be_nil
    end

    it 'returns nil instead of breaking the scheduler for a malformed timestamp' do
      event.update!(
        weather_history: [
          {
            timestamp: 'not-a-time',
            weather_data: { temp_c: 10 }
          }
        ]
      )

      expect(described_class.get_fallback_weather(event.reload)).to be_nil
    end
  end

  describe '.report' do
    let(:notifier) { RecordingNotifier.new }

    before do
      use_app_config('WEATHER_ADMIN_ALERTS' => true)
      described_class.admin_notifier = notifier
    end

    it 'forwards errors to the configured administrator notifier' do
      described_class.report(:error, 'Weather API unavailable', status: 503)

      expect(notifier.alerts).to eq(
        [[:error, 'Weather API unavailable', { status: 503 }]]
      )
    end

    it 'forwards a repeated timeout warning' do
      described_class.report(:warn, 'Retrying after timeout', retry_count: 1)

      expect(notifier.alerts).to eq(
        [[:warn, 'Retrying after timeout', { retry_count: 1 }]]
      )
    end

    it 'does not forward an ordinary warning' do
      described_class.report(:warn, 'Using stored fallback weather data', event_id: 42)

      expect(notifier.alerts).to be_empty
    end
  end
end
