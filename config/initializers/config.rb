require 'yaml'
require 'active_support/time'

ENV['RACK_ENV'] ||= 'development'

require_relative '../app_config'

APP_CONFIG = AppConfig.load(root: VELO_UTRO_ROOT) unless defined?(APP_CONFIG)

Time.zone = APP_CONFIG.timezone
