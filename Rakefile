require 'sinatra/activerecord/rake'
require './app'

namespace :db do
  task :load_config do
    require './config/database'
  end
end

desc 'Start the bot'
task :start do
  ruby 'app.rb'
end

desc 'Start the bot in development mode with auto-reload'
task :dev do
  sh 'shotgun app.rb'
end

desc 'Start an interactive console'
task :console do
  require 'pry'
  require './app'
  ARGV.clear
  Pry.start
end