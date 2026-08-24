require 'spec_helper'

RSpec.describe Bot::Helpers::Formatter do
  describe '.format_time' do
    it 'returns the start of a legacy time range without trailing whitespace' do
      expect(described_class.format_time('9:00 - 10:30')).to eq('9:00')
    end

    it 'keeps an exact time and removes seconds' do
      expect(described_class.format_time('09:30')).to eq('09:30')
      expect(described_class.format_time('09:30:45')).to eq('09:30')
    end
  end

  describe '.format_weather' do
    it 'normalizes symbol keys and displays significant weather values' do
      text = described_class.format_weather(
        temp_c: 12,
        feelslike_c: 9,
        condition: 'Дождь',
        wind_kph: 26,
        precip_prob: 80,
        humidity: 90,
        uv: 7
      )

      expect(text).to include(
        '🌧️ Дождь, 12°C',
        '(ощущ. 9°C)',
        '🌪️ 26 км/ч',
        '🌧️ 80%',
        '💧 90%',
        '☀️ УФ 7'
      )
    end

    it 'returns nil for a non-hash value' do
      expect(described_class.format_weather(nil)).to be_nil
      expect(described_class.format_weather('sunny')).to be_nil
    end

    it 'uses a condition-specific emoji for supported Russian descriptions' do
      expectations = {
        'Ливень' => '🌧️',
        'Гроза' => '⛈️',
        'Снег' => '🌨️',
        'Морось' => '🌦️',
        'Солнечно' => '☀️',
        'Переменная облачность' => '⛅',
        'Пасмурно' => '☁️',
        'Туман' => '🌫️',
        'Ветрено' => '💨'
      }

      expectations.each do |condition, emoji|
        expect(described_class.format_weather('condition' => condition, 'temp_c' => 15))
          .to start_with(emoji)
      end
    end

    it 'falls back to temperature ranges when a condition is unknown' do
      expectations = {
        -11 => '🥶',
        -1 => '❄️',
        10 => '🌤️',
        25 => '☀️',
        30 => '🥵'
      }

      expectations.each do |temperature, emoji|
        weather = { 'condition' => 'Неизвестно', 'temp_c' => temperature }
        expect(described_class.format_weather(weather)).to start_with(emoji)
      end
    end

    it 'uses stable wind and precipitation threshold emojis' do
      calm = described_class.format_weather(
        'condition' => 'Ясно',
        'temp_c' => 15,
        'wind_kph' => 5,
        'precip_prob' => 10
      )
      moderate = described_class.format_weather(
        'condition' => 'Ясно',
        'temp_c' => 15,
        'wind_kph' => 15,
        'precip_prob' => 50
      )
      dangerous = described_class.format_weather(
        'condition' => 'Ясно',
        'temp_c' => 15,
        'wind_kph' => 45,
        'precip_prob' => 80
      )

      expect(calm).to include('🍃 5 км/ч', '🌦️ 10%')
      expect(moderate).to include('💨 15 км/ч', '☔ 50%')
      expect(dangerous).to include('⚠️ 45 км/ч', '🌧️ 80%')
    end
  end

  describe '.format_weather_detailed' do
    it 'adds equipment recommendations as a readable list' do
      text = described_class.format_weather_detailed(
        'temp_c' => -2,
        'feelslike_c' => -5,
        'condition' => 'Снег',
        'wind_kph' => 15,
        'precip_prob' => 90
      )

      expect(text).to include('🌤️ Прогноз погоды:', '⚡ Рекомендации:', '• 🥶 Мороз!')
    end
  end
end
