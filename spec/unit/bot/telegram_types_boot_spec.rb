require 'spec_helper'
require 'open3'
require 'rbconfig'

RSpec.describe 'Telegram type loading' do
  it 'loads CallbackQuery first in a fresh application process' do
    script = <<~RUBY
      require './config/environment'
      Telegram::Bot::Types::CallbackQuery
    RUBY

    _stdout, stderr, status = Open3.capture3(
      {
        'RACK_ENV' => 'test',
        'DB_NAME' => 'velo_utro_bot_test',
        'DB_HOST' => '127.0.0.1',
        'DB_PORT' => '55432'
      },
      RbConfig.ruby,
      '-e',
      script,
      chdir: VELO_UTRO_ROOT
    )

    expect(status).to be_success, stderr
  end
end
