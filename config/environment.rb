require 'dotenv/load'
require 'telegram/bot'

# telegram-bot-ruby 2.4 has a circular autoload between CallbackQuery and
# MaybeInaccessibleMessage. Loading Message first makes both update types safe.
Telegram::Bot::Types::Message

require 'sinatra/base'
require 'sinatra/activerecord'
require 'json'
require 'yaml'
require 'mustache'
require 'i18n'
require 'logger'
require 'ostruct'

VELO_UTRO_ROOT = File.expand_path('..', __dir__) unless defined?(VELO_UTRO_ROOT)

require_relative 'initializers/config'
require_relative 'app_clock'
require_relative 'app_logger'
require_relative 'initializers/i18n'

APP_LOGGER = Logger.new($stdout) unless defined?(APP_LOGGER)
APP_LOGGER.level = if APP_CONFIG.production? && !APP_CONFIG.weather_debug?
  Logger::INFO
else
  Logger::DEBUG
end
APP_LOGGER.progname = 'velo_utro_bot'
APP_STARTED_AT = AppClock.now unless defined?(APP_STARTED_AT)

require_relative 'database'
require_relative '../app/services/event_time'

Dir[File.join(VELO_UTRO_ROOT, 'app', 'models', '*.rb')].sort.each { |file| require file }

require_relative '../app/services/service_result'
Dir[File.join(VELO_UTRO_ROOT, 'app', 'services', 'events', '*.rb')].sort.each { |file| require file }
Dir[File.join(VELO_UTRO_ROOT, 'app', 'services', 'notifications', '*.rb')].sort.each { |file| require file }
require_relative '../app/services/weather_service'
require_relative '../app/services/weather_recommendations'

require_relative '../app/bot/helpers/formatter'
require_relative '../app/bot/helpers/notifier'
require_relative '../app/bot/helpers/weather_notifier'
require_relative '../app/bot/helpers/calendar'
require_relative '../app/bot/helpers/scheduler'
require_relative '../app/bot/helpers/weather_scheduler'
require_relative '../app/bot/helpers/weather_admin_notifier'
require_relative '../app/bot/helpers/statistics'
require_relative '../app/bot/base_handler'
require_relative '../app/bot/command_handler'
require_relative '../app/bot/callback_handler'
require_relative '../app/bot/state_handler'
require_relative '../app/bot/commands'
require_relative '../app/bot/callbacks'
require_relative '../app/bot/states'
