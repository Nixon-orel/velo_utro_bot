require 'yaml'
require 'active_support/time'

ActiveSupport.to_time_preserves_timezone = :zone

ENV['RACK_ENV'] ||= 'development'

require_relative '../app_config'

APP_CONFIG = AppConfig.load(root: VELO_UTRO_ROOT) unless defined?(APP_CONFIG)

Time.zone = APP_CONFIG.timezone
