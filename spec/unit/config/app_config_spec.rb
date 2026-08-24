require 'spec_helper'
require 'fileutils'
require 'tmpdir'

RSpec.describe AppConfig do
  describe '.load' do
    it 'loads the selected environment YAML and lets explicit environment variables override it' do
      Dir.mktmpdir('velo-utro-app-config') do |root|
        environment_directory = File.join(root, 'config', 'environments')
        FileUtils.mkdir_p(environment_directory)
        File.write(
          File.join(environment_directory, 'test.yml'),
          <<~YAML
            TIMEZONE: UTC
            WEATHER_ENABLED: false
            PORT: 3000
          YAML
        )

        config = described_class.load(
          root: root,
          env: {
            'RACK_ENV' => 'test',
            'WEATHER_ENABLED' => 'true',
            'PORT' => '9292'
          }
        )

        expect(config).to have_attributes(
          environment: 'test',
          timezone: 'UTC',
          port: 9292
        )
        expect(config).to be_weather_enabled
      end
    end

    it 'loads daily announcement settings from environment variables' do
      config = described_class.load(
        root: Dir.mktmpdir('velo-utro-app-config'),
        env: {
          'RACK_ENV' => 'test',
          'DAILY_ANNOUNCEMENT_ENABLED' => 'true',
          'DAILY_ANNOUNCEMENT_TIME' => '07:30'
        }
      )

      expect(config).to be_daily_announcement_enabled
      expect(config.daily_announcement_time).to eq('07:30')
    end
  end

  describe 'normalization' do
    it 'normalizes lists, booleans, numeric values, and legacy city name' do
      config = described_class.new(
        'RACK_ENV' => 'test',
        'ADMIN_IDS' => ' 10, 20, ',
        'STATIC_EVENTS' => ['Ride', ' Walk '],
        'EVENT_TYPES' => [:ride, 'walk'],
        'MONTHLY_STATS_DAY' => '31',
        'TIMEZONE' => 'UTC',
        'WEATHER_ENABLED' => true,
        'WEATHER_ADMIN_ALERTS' => 'false',
        'WEATHER_DEBUG' => 'true',
        'DEFAULT_WEATHER_CITY' => 'Курск',
        'PORT' => '9292'
      )

      expect(config.admin_ids).to eq(%w[10 20])
      expect(config.static_events).to eq(['Ride', 'Walk'])
      expect(config.event_types).to eq(%w[ride walk])
      expect(config.monthly_stats_day).to eq(28)
      expect(config).to be_weather_enabled
      expect(config).not_to be_weather_admin_alerts
      expect(config).to be_weather_debug
      expect(config.default_weather_city).to eq('Курск')
      expect(config.port).to eq(9292)
    end

    it 'uses safe defaults for optional settings' do
      config = described_class.new('RACK_ENV' => 'test')

      expect(config.timezone).to eq('Europe/Moscow')
      expect(config.monthly_stats_day).to be_nil
      expect(config.admin_ids).to eq([])
      expect(config).not_to be_daily_announcement_enabled
      expect(config.daily_announcement_time).to eq('08:00')
      expect(config).not_to be_weather_enabled
    end
  end

  describe 'validation' do
    it 'rejects an unknown timezone' do
      expect do
        described_class.new('RACK_ENV' => 'test', 'TIMEZONE' => 'Mars/Olympus')
      end.to raise_error(described_class::InvalidConfiguration, /Unknown TIMEZONE/)
    end

    it 'rejects a daily announcement time outside HH:MM format' do
      expect do
        described_class.new('RACK_ENV' => 'test', 'DAILY_ANNOUNCEMENT_TIME' => '25:00')
      end.to raise_error(described_class::InvalidConfiguration, /DAILY_ANNOUNCEMENT_TIME/)
    end
  end
end
