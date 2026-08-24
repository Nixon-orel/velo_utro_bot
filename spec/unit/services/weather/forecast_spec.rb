require 'spec_helper'

RSpec.describe Weather::Forecast do
  def forecast_data
    {
      'forecast' => {
        'forecastday' => [
          {
            'date' => '2026-08-22',
            'hour' => [
              {
                'time' => '2026-08-22 09:00',
                'temp_c' => 18.5,
                'feelslike_c' => 17.0,
                'condition' => { 'text' => 'Ясно', 'icon' => '//icon' },
                'wind_kph' => 12.0,
                'wind_dir' => 'W',
                'precip_mm' => 0.0,
                'chance_of_rain' => 10,
                'humidity' => 50,
                'uv' => 3
              }
            ],
            'day' => {
              'avgtemp_c' => 16.0,
              'condition' => { 'text' => 'Облачно', 'icon' => '//daily-icon' },
              'maxwind_kph' => 20.0,
              'totalprecip_mm' => 1.2,
              'daily_chance_of_rain' => 60,
              'avghumidity' => 70,
              'uv' => 2
            },
            'astro' => { 'sunrise' => '05:00 AM', 'sunset' => '08:00 PM' }
          },
          {
            'date' => '2026-08-23',
            'hour' => [],
            'day' => {
              'avgtemp_c' => 15.0,
              'condition' => { 'text' => 'Дождь', 'icon' => '//rain' },
              'maxwind_kph' => 25.0,
              'totalprecip_mm' => 3.0,
              'daily_chance_of_rain' => 90,
              'avghumidity' => 85,
              'uv' => 1
            },
            'astro' => { 'sunrise' => '05:02 AM', 'sunset' => '07:58 PM' }
          }
        ]
      },
      'alerts' => { 'alert' => [{ 'event' => 'Strong wind' }] }
    }
  end

  describe '.for_event' do
    it 'selects the forecast hour matching the event start hour' do
      forecast = described_class.for_event(
        data: forecast_data,
        event_date: Date.new(2026, 8, 22),
        event_time: '09:30'
      )

      expect(forecast).to include(
        'temp_c' => 18.5,
        'condition' => 'Ясно',
        'forecast_date' => '2026-08-22',
        'forecast_time' => '09:30',
        'is_fallback' => false,
        'sunset' => '08:00 PM'
      )
      expect(forecast['alerts']).to eq([{ 'event' => 'Strong wind' }])
    end

    it 'uses daily values when the requested hour is unavailable' do
      forecast = described_class.for_event(
        data: forecast_data,
        event_date: '2026-08-22',
        event_time: '21:00'
      )

      expect(forecast).to include(
        'temp_c' => 16.0,
        'feelslike_c' => 16.0,
        'condition' => 'Облачно',
        'precip_prob' => 60
      )
    end

    it 'marks the last available day as fallback for an out-of-range date' do
      forecast = described_class.for_event(
        data: forecast_data,
        event_date: '2026-08-30',
        event_time: '12:00'
      )

      expect(forecast).to include(
        'condition' => 'Дождь',
        'forecast_date' => '2026-08-30',
        'is_fallback' => true,
        'fallback_from' => '2026-08-23'
      )
    end

    it 'returns nil when no forecast day exists' do
      expect(
        described_class.for_event(
          data: { 'forecast' => { 'forecastday' => [] } },
          event_date: '2026-08-22',
          event_time: '09:00'
        )
      ).to be_nil
    end
  end

  describe '.normalize' do
    it 'recursively converts hash keys to strings' do
      normalized = described_class.normalize(alerts: [{ event: 'Wind' }], nested: { value: 1 })

      expect(normalized).to eq(
        'alerts' => [{ 'event' => 'Wind' }],
        'nested' => { 'value' => 1 }
      )
    end
  end
end
