require 'dotenv/load'
require 'sinatra/activerecord'

require_relative 'config/database'

ActiveRecord::MigrationContext.new('db/migrations/').migrate
puts "Migrations completed successfully!"