require_relative 'update_router'

module Bot
  class Runner
    SHUTDOWN_SIGNAL = '.'.freeze

    GROUP_COMMANDS = [
      { command: 'start', description: 'Начать работу с ботом' },
      { command: 'menu', description: 'Показать главное меню' },
      { command: 'create', description: 'Создать новое мероприятие' },
      { command: 'find', description: 'Найти мероприятие' },
      { command: 'my_events', description: 'Мои мероприятия' },
      { command: 'help', description: 'Справка по использованию' }
    ].freeze

    PRIVATE_COMMANDS = [
      { command: 'start', description: 'Начать работу с ботом' },
      { command: 'menu', description: 'Показать главное меню' },
      { command: 'create', description: 'Создать новое мероприятие' },
      { command: 'find', description: 'Найти мероприятие' },
      { command: 'my_events', description: 'Мои мероприятия' },
      { command: 'subscribe', description: 'Подписаться на уведомления о событиях' },
      { command: 'unsubscribe', description: 'Отписаться от уведомлений' },
      { command: 'help', description: 'Справка по использованию' },
      { command: 'statistics', description: 'Статистика за месяц (админ)' }
    ].freeze

    def self.run(token: APP_CONFIG.telegram_token)
      if token.nil? || token.empty?
        AppLogger.error('Bot::Runner', 'Telegram token is not set')
        return false
      end

      Telegram::Bot::Client.run(token) do |bot|
        new(bot).run
      end

      true
    end

    def initialize(bot)
      @bot = bot
      @update_router = UpdateRouter.new(bot)
    end

    def run
      AppLogger.info('Bot::Runner', 'Bot started')
      configure_telegram
      start_schedulers
      install_signal_handlers
      listen
    end

    private

    def configure_telegram
      configure_commands(GROUP_COMMANDS, 'all_group_chats', 'Group commands set (redirect to private)')
      configure_commands(PRIVATE_COMMANDS, 'all_private_chats', 'Private commands set (full functionality)')
      configure_menu_button
    end

    def configure_commands(commands, scope_type, success_message)
      @bot.api.set_my_commands(commands: commands, scope: { type: scope_type })
      AppLogger.info('Bot::Runner', success_message, scope: scope_type)
    rescue => e
      AppLogger.error('Bot::Runner', 'Failed to set commands', scope: scope_type, exception: e)
    end

    def configure_menu_button
      @bot.api.set_chat_menu_button(
        menu_button: { type: 'commands' }
      )
      AppLogger.info('Bot::Runner', 'Default private-chat menu button enabled')
    rescue => e
      AppLogger.error('Bot::Runner', 'Failed to enable menu button', exception: e)
    end

    def start_schedulers
      WeatherService.admin_notifier = Bot::Helpers::WeatherAdminNotifier.new(@bot)
      Bot::Helpers::Scheduler.start(@bot)
      Bot::Helpers::WeatherScheduler.start(@bot)
    end

    def install_signal_handlers
      @shutdown_reader, @shutdown_writer = IO.pipe
      @shutdown_thread = Thread.new do
        @shutdown_reader.read(1)
        shutdown
      end

      %w[INT TERM].each do |signal|
        Signal.trap(signal) do
          @shutdown_writer.write_nonblock(SHUTDOWN_SIGNAL)
        rescue IO::WaitWritable, IOError
          nil
        end
      end
    end

    def shutdown
      AppLogger.info('Bot::Runner', 'Shutting down')
      Bot::Helpers::Scheduler.stop
      Bot::Helpers::WeatherScheduler.stop
      exit
    end

    def listen
      @bot.listen do |update|
        @update_router.call(update)
      end
    end
  end
end
