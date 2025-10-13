require 'dotenv/load'
require 'telegram/bot'
require 'sinatra/base'
require 'sinatra/activerecord'
require 'json'
require 'yaml'
require 'mustache'
require 'i18n'
require 'logger'
require 'ostruct'

$PROGRAM_START_TIME = Time.now.to_i

require_relative 'config/initializers/config'
require_relative 'config/initializers/i18n'
require_relative 'config/database'

Dir[File.join(File.dirname(__FILE__), 'app', 'models', '*.rb')].each { |file| require file }

require_relative 'app/bot/helpers/formatter'
require_relative 'app/bot/helpers/notifier'
require_relative 'app/bot/helpers/weather_notifier'
require_relative 'app/bot/helpers/calendar'
require_relative 'app/bot/helpers/scheduler'
require_relative 'app/bot/helpers/weather_scheduler'
require_relative 'app/bot/helpers/statistics'
require_relative 'app/bot/base_handler'
require_relative 'app/bot/command_handler'
require_relative 'app/bot/callback_handler'
require_relative 'app/bot/state_handler'
require_relative 'app/bot/commands'
require_relative 'app/bot/callbacks'
require_relative 'app/bot/states'

logger = Logger.new(STDOUT)
logger.level = ENV['RACK_ENV'] == 'production' ? Logger::INFO : Logger::DEBUG

class App < Sinatra::Base
  register Sinatra::ActiveRecordExtension
  
  configure do
    set :root, File.dirname(__FILE__)
    set :public_folder, File.join(settings.root, 'public')
    set :views, File.join(settings.root, 'app', 'views')
    set :port, ENV['PORT'] || 4567
    set :bind, '0.0.0.0'
  end
  
  get '/' do
    'Velo Utro Bot'
  end
  
  get '/about' do
    <<~HTML
      <h1>Velo Utro Bot</h1>
      <b>© Aldushkin Nikita, 2025</b>
    HTML
  end
  
  get '/publish-today-events' do
    begin
      events = Event.today
      
      if events.empty?
        'No events scheduled for today.'
      else
        "#{events.length} events published successfully."
      end
    rescue => e
      "An error occurred while publishing events: #{e.message}"
    end
  end
end

def run_bot
  token = ENV['TG_TOKEN']
  
  if token.nil? || token.empty?
    puts "ERROR: Telegram token is not set. Please set TG_TOKEN environment variable."
    return
  end
  
  Telegram::Bot::Client.run(token) do |bot|
    puts "Bot started"
    
    begin
      group_commands = [
        { command: 'start', description: 'Начать работу с ботом' },
        { command: 'menu', description: 'Показать главное меню' },
        { command: 'create', description: 'Создать новое мероприятие' },
        { command: 'find', description: 'Найти мероприятие' },
        { command: 'my_events', description: 'Мои мероприятия' },
        { command: 'help', description: 'Справка по использованию' }
      ]
      
      bot.api.set_my_commands(
        commands: group_commands,
        scope: { type: 'all_group_chats' }
      )
      puts "Group commands set (redirect to private)"
    rescue => e
      puts "Failed to set group commands: #{e.message}"
    end

    begin
      private_commands = [
        { command: 'start', description: 'Начать работу с ботом' },
        { command: 'menu', description: 'Показать главное меню' },
        { command: 'create', description: 'Создать новое мероприятие' },
        { command: 'find', description: 'Найти мероприятие' },
        { command: 'my_events', description: 'Мои мероприятия' },
        { command: 'help', description: 'Справка по использованию' },
        { command: 'statistics', description: 'Статистика за месяц (админ)' }
      ]
      
      bot.api.set_my_commands(
        commands: private_commands,
        scope: { type: 'all_private_chats' }
      )
      puts "Private commands set (full functionality)"
    rescue => e
      puts "Failed to set private commands: #{e.message}"
    end

    begin
      bot.api.set_chat_menu_button(
        menu_button: { type: 'commands' },
        scope: { type: 'all_group_chats' }
      )
      puts "Group menu button enabled"
    rescue => e
      puts "Failed to enable group menu button: #{e.message}"
    end

    begin
      bot.api.set_chat_menu_button(
        menu_button: { type: 'commands' },
        scope: { type: 'all_private_chats' }
      )
      puts "Private menu button enabled"
    rescue => e
      puts "Failed to enable private menu button: #{e.message}"
    end
    
    Bot::Helpers::Scheduler.start(bot)
    Bot::Helpers::WeatherScheduler.start
    
    Signal.trap('INT') do
      puts "\nShutting down..."
      Bot::Helpers::Scheduler.stop
      Bot::Helpers::WeatherScheduler.stop
      exit
    end
    
    Signal.trap('TERM') do
      puts "\nShutting down..."
      Bot::Helpers::Scheduler.stop
      Bot::Helpers::WeatherScheduler.stop
      exit
    end
    
    bot.listen do |message|
      begin
        case message
        when Telegram::Bot::Types::Message
          next unless message.from
          user_id = message.from.id.to_s
          session = Session.load(user_id)
          
          if message.text&.start_with?('/')
            command = message.text.split(' ').first[1..-1].split('@').first
            
            if message.chat.type == 'private'
              Bot::Commands.execute(command, bot, message, session)
            else
              bot_username = ENV['BOT_USERNAME']
              if bot_username && !bot_username.empty?
                bot.api.send_message(
                  chat_id: message.chat.id,
                  text: "Для использования команд бота перейдите в личные сообщения:",
                  reply_markup: Telegram::Bot::Types::InlineKeyboardMarkup.new(
                    inline_keyboard: [[
                      Telegram::Bot::Types::InlineKeyboardButton.new(
                        text: "💬 Открыть чат с ботом",
                        url: "https://t.me/#{bot_username}?start=#{command}"
                      )
                    ]]
                  )
                )
              else
                bot.api.send_message(
                  chat_id: message.chat.id,
                  text: "Для использования команд бота перейдите в личные сообщения с @#{bot.api.get_me['result']['username']}"
                )
              end
            end
          elsif session.state
            next unless message.chat.type == 'private'
            Bot::States.process(session.state, bot, message, session)
          else
            next unless message.chat.type == 'private'
            bot.api.send_message(
              chat_id: message.chat.id,
              text: I18n.t('unknown_command')
            )
          end
        when Telegram::Bot::Types::CallbackQuery
          next unless message.from
          user_id = message.from.id.to_s
          
          unless message.message.chat.type == 'private'
            action = message.data.split('-')[0]
            next unless ['join', 'unjoin'].include?(action)
            session = OpenStruct.new(data: {})
          else
            session = Session.load(user_id)
          end
          
          if message.data.start_with?('calendar')
            calendar_type = session.calendar_type
            calendar = Bot::Helpers::Calendar.new
            result = calendar.handle_callback(bot, message)
            
            if result
              if session.state == 'choose_date'
                session.new_event['date'] = result
                session.state = 'choose_time'
                session.save_session
                
                bot.api.send_message(
                  chat_id: message.message.chat.id,
                  text: I18n.t('choose_time'),
                  parse_mode: 'HTML'
                )
              elsif session.state == 'edit_date'
                event_id = session.edit_event_id
                event = Event.find_by(id: event_id)
                
                if event && event.author_id == User.find_or_create_from_telegram(message.from).id
                  old_date = event.formatted_date
                  event.update(date: Date.parse(result))
                  new_date = event.formatted_date
                  
                  notifier = Bot::Helpers::Notifier.new(bot)
                  notifier.notify_participants(event, 'date_changed_notification', { new_date: new_date })
                  notifier.notify_channel_about_change(event, 'date_changed_channel_notification', { new_date: new_date })
                  
                  if event.weather_data.present? && ENV['WEATHER_ENABLED'] == 'true'
                    Bot::Helpers::WeatherScheduler.schedule_weather_updates(event)
                    puts "[Calendar] Rescheduled weather updates for event #{event.id}"
                  end
                  
                  session.state = nil
                  session.edit_event_id = nil
                  session.save_session
                  
                  bot.api.send_message(
                    chat_id: message.message.chat.id,
                    text: I18n.t('date_saved'),
                    parse_mode: 'HTML'
                  )
                  
                  bot.api.send_message(
                    chat_id: message.message.chat.id,
                    text: I18n.t('event_updated'),
                    parse_mode: 'HTML'
                  )
                end
              elsif session.state == 'find_events_on_date'
                date = Date.parse(result)
                next_date = date + 1
                events = Event.for_period(date, next_date)
                
                handler = Bot::CallbackHandler.new(bot, message, session)
                handler.send(:display_events, events, I18n.t('buttons.find_date'), I18n.t('no_upcoming_events'))
              end
            end
          elsif message.data.include?('-')
            Bot::Callbacks.process(message.data, bot, message, session)
          else
            event_type = message.data
            
            if CONFIG['EVENT_TYPES'].include?(event_type)
              session.new_event['type'] = event_type
              session.state = 'choose_location'
              session.save_session
              
              bot.api.send_message(
                chat_id: message.message.chat.id,
                text: I18n.t('choose_location'),
                parse_mode: 'HTML'
              )
            else
              Bot::Callbacks.process(message.data, bot, message, session)
            end
          end
        end
      rescue => e
        puts "Error: #{e.message}"
        puts e.backtrace.join("\n")
      end
    end
  end
end

if ENV['RACK_ENV'] == 'production'
  App.run!
else
  run_bot
end