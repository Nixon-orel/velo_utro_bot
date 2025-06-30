require 'sinatra/activerecord'
require 'yaml'
require 'erb'
require 'dotenv/load'

env = ENV['RACK_ENV'] || 'development'

database_yml_path = File.join(File.dirname(__FILE__), 'database.yml')
database_yml_content = File.read(database_yml_path)
erb_processed = ERB.new(database_yml_content).result
db_config = YAML.load(erb_processed, aliases: true)[env]

ActiveRecord::Base.establish_connection(db_config)

if env == 'development'
  ActiveRecord::Base.logger = Logger.new(STDOUT)
end