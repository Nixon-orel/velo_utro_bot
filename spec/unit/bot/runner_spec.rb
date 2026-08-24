require 'spec_helper'
require_relative '../../../app/bot/runner'

RSpec.describe Bot::Runner do
  let(:api) do
    Class.new do
      attr_reader :command_sets, :menu_buttons
      attr_accessor :failing_command_scope, :menu_error

      def initialize
        @command_sets = []
        @menu_buttons = []
      end

      def set_my_commands(**payload)
        @command_sets << payload
        raise 'commands failed' if payload.dig(:scope, :type) == failing_command_scope
      end

      def set_chat_menu_button(**payload)
        @menu_buttons << payload
        raise menu_error if menu_error
      end
    end.new
  end
  let(:bot) { Struct.new(:api).new(api) }

  it 'refuses to start Telegram polling without a token' do
    expect(Telegram::Bot::Client).not_to receive(:run)

    expect(described_class.run(token: '')).to be(false)
  end

  it 'configures scoped commands and one default private-chat menu button' do
    described_class.new(bot).send(:configure_telegram)

    expect(api.command_sets).to eq(
      [
        {
          commands: described_class::GROUP_COMMANDS,
          scope: { type: 'all_group_chats' }
        },
        {
          commands: described_class::PRIVATE_COMMANDS,
          scope: { type: 'all_private_chats' }
        }
      ]
    )
    expect(api.menu_buttons).to eq([{ menu_button: { type: 'commands' } }])
  end

  it 'stops both schedulers before exiting' do
    runner = described_class.new(bot)
    expect(Bot::Helpers::Scheduler).to receive(:stop).ordered
    expect(Bot::Helpers::WeatherScheduler).to receive(:stop).ordered

    expect { runner.send(:shutdown) }.to raise_error(SystemExit) do |error|
      expect(error.status).to eq(0)
    end
  end

  it 'isolates Telegram configuration failures between setup steps' do
    api.failing_command_scope = 'all_group_chats'
    api.menu_error = Faraday::TimeoutError.new('timeout')

    expect { described_class.new(bot).send(:configure_telegram) }.not_to raise_error
    expect(api.command_sets.map { |payload| payload.dig(:scope, :type) }).to eq(
      %w[all_group_chats all_private_chats]
    )
    expect(api.menu_buttons).to eq([{ menu_button: { type: 'commands' } }])
  end
end
