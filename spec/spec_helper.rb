ENV['RACK_ENV'] = 'test'
ENV['DB_NAME'] ||= 'velo_utro_bot_test'
ENV['DB_HOST'] ||= '127.0.0.1'
ENV['DB_PORT'] ||= '55432'
ENV['DB_USER'] ||= 'postgres'
ENV['DB_PASSWORD'] ||= 'postgres'

require 'simplecov'

SimpleCov.start do
  enable_coverage :branch
  primary_coverage :line
  skip '/spec/'
  cover '{app,config}/**/*.rb'
end

require 'webmock/rspec'
require_relative '../config/environment'

APP_LOGGER.level = Logger::FATAL

unless APP_CONFIG.environment == 'test'
  abort "RSpec must run in test environment, got #{APP_CONFIG.environment.inspect}"
end

database_name = ActiveRecord::Base.connection_db_config.database.to_s
unless database_name.end_with?('_test')
  abort "RSpec refuses to use non-test database #{database_name.inspect}"
end

WebMock.disable_net_connect!(allow_localhost: true)

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.example_status_persistence_file_path = '.rspec_status'
  config.filter_run_when_matching :focus
  config.order = :random
  Kernel.srand config.seed

  config.expect_with :rspec do |expectations|
    expectations.syntax = :expect
  end

  config.after do
    AppClock.reset!
    WeatherService.reset_client!
  end
end
