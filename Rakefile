require 'sinatra/activerecord/rake'
require_relative 'config/environment'

ActiveRecord::Tasks::DatabaseTasks.migrations_paths = [File.join(VELO_UTRO_ROOT, 'db', 'migrations')]

namespace :db do
  task :load_config do
    require './config/database'
  end
end

desc 'Start the bot'
task :start do
  ruby 'bin/bot'
end

desc 'Start the web app in development mode with auto-reload'
task :dev do
  sh 'shotgun app.rb'
end

desc 'Start an interactive console'
task :console do
  require 'pry'
  ARGV.clear
  Pry.start
end
