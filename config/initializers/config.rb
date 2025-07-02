require 'yaml'
require 'active_support/time'

ENV['RACK_ENV'] ||= 'development'
environment = ENV['RACK_ENV']

config_file = File.join(File.dirname(__FILE__), "../environments/#{environment}.yml")
CONFIG = YAML.load_file(config_file, aliases: true) if File.exist?(config_file)

CONFIG ||= {}
CONFIG['TG_TOKEN'] = ENV['TG_TOKEN']
CONFIG['PUBLIC_CHANNEL_ID'] = ENV['PUBLIC_CHANNEL_ID']
CONFIG['BOT_USERNAME'] = ENV['BOT_USERNAME']
CONFIG['WEBHOOK_DOMAIN'] ||= ENV['WEBHOOK_DOMAIN']
CONFIG['ADMIN_IDS'] = ENV['ADMIN_IDS'].to_s.split(',').map(&:strip) if ENV['ADMIN_IDS']
CONFIG['STATIC_EVENTS'] ||= ENV['STATIC_EVENTS'].to_s.split(',').map(&:strip)

CONFIG['DAILY_ANNOUNCEMENT_ENABLED'] = ENV['DAILY_ANNOUNCEMENT_ENABLED'] == 'true'
CONFIG['DAILY_ANNOUNCEMENT_TIME'] = ENV['DAILY_ANNOUNCEMENT_TIME'] || '08:00'
CONFIG['TIMEZONE'] = ENV['TIMEZONE'] || 'Europe/Moscow'

Time.zone = CONFIG['TIMEZONE']