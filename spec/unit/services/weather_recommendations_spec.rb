require 'spec_helper'

RSpec.describe WeatherRecommendations do
  describe '.generate' do
    it 'returns no recommendations without weather data' do
      expect(described_class.generate(nil)).to eq([])
      expect(described_class.generate({})).to eq([])
    end

    it 'warns about freezing weather' do
      recommendations = described_class.generate('feelslike_c' => -1)

      expect(recommendations).to include(
        '🥶 Мороз! Полная зимняя экипировка',
        '⚠️ Осторожно - возможен гололед!'
      )
    end

    it 'recommends sun protection in hot weather' do
      recommendations = described_class.generate('feelslike_c' => 25)

      expect(recommendations).to include('💧 Возьмите больше воды', '☀️ Солнцезащитный крем')
    end

    it 'reacts to rain, fog, and dangerous wind' do
      recommendations = described_class.generate(
        'feelslike_c' => 18,
        'precip_prob' => 80,
        'condition' => 'Туман',
        'wind_kph' => 31
      )

      expect(recommendations).to include(
        '☔ Дождевик обязателен',
        '🔦 Мощный задний фонарь',
        '⚠️ ОПАСНЫЙ ветер!'
      )
    end

    it 'adds lighting advice during the two hours before sunset' do
      recommendations = described_class.generate(
        { 'feelslike_c' => 18, 'sunset' => '08:30 PM' },
        '18:30'
      )

      expect(recommendations).to include(
        '🔦 Фонари обязательны (скоро темно)',
        '🔆 Светоотражающие элементы'
      )
    end

    it 'adds lighting advice for an early morning ride' do
      recommendations = described_class.generate(
        { 'feelslike_c' => 18, 'sunset' => '08:30 PM' },
        '06:00'
      )

      expect(recommendations).to include('🔦 Фонари для утренней поездки')
    end

    it 'normalizes alerts and removes repeated advice' do
      recommendations = described_class.generate(
        'feelslike_c' => 18,
        'alerts' => [
          { event: 'Strong wind' },
          { 'event' => 'Strong wind' }
        ]
      )

      expect(recommendations.count('💨 Штормовое предупреждение по ветру!')).to eq(1)
    end

    it 'ignores an invalid event time instead of failing the recommendation flow' do
      weather = {
        'feelslike_c' => 18,
        'sunset' => '08:30 PM'
      }

      expect(described_class.generate(weather, 'not-a-time')).to include('👕 Идеальная погода! Легкая одежда')
    end
  end
end
