require 'spec_helper'
require 'open3'
require 'rbconfig'

RSpec.describe 'application boot' do
  it 'loads the compatibility entrypoint without starting a runtime' do
    script = <<~RUBY
      require './app'
      abort 'App is not loaded' unless defined?(App)
      abort 'Bot::Runner is not loaded' unless defined?(Bot::Runner)
    RUBY

    _stdout, stderr, status = Open3.capture3(
      {
        'RACK_ENV' => 'test',
        'DB_NAME' => 'velo_utro_bot_test',
        'DB_HOST' => '127.0.0.1',
        'DB_PORT' => '55432',
        'DB_USER' => 'postgres',
        'DB_PASSWORD' => 'postgres',
        'TG_TOKEN' => ''
      },
      'timeout',
      '5s',
      RbConfig.ruby,
      '-e',
      script,
      chdir: VELO_UTRO_ROOT
    )

    expect(status).to be_success, stderr
  end
end
