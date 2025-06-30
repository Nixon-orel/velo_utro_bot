require 'rufus-scheduler'

module Bot
  module Helpers
    class Scheduler
      def initialize(bot)
        @bot = bot
        @scheduler = Rufus::Scheduler.new
      end
      
      def start
        return unless CONFIG['DAILY_ANNOUNCEMENT_ENABLED']
        
        time = CONFIG['DAILY_ANNOUNCEMENT_TIME']
        timezone = CONFIG['TIMEZONE'] || 'Europe/Moscow'
        puts "Starting daily announcement scheduler at #{time} (#{timezone})"
        
        @scheduler.cron "0 #{parse_time(time)} * * *", timezone: timezone do
          send_daily_announcement
        end
        
        puts "Daily announcement scheduler started successfully"
      end
      
      def stop
        @scheduler.shutdown
        puts "Scheduler stopped"
      end
      
      private
      
      def parse_time(time_string)
        hour, minute = time_string.split(':').map(&:to_i)
        "#{minute} #{hour}"
      end
      
      def send_daily_announcement
        begin
          puts "Sending daily announcement..."
          
          events = Event.next_24_hours
          
          channel_id = CONFIG['PUBLIC_CHANNEL_ID']
          return unless channel_id
          
          if events.empty?
            @bot.api.send_message(
              chat_id: channel_id,
              text: I18n.t('daily_announcement_no_events'),
              parse_mode: 'HTML'
            )
          else
            @bot.api.send_message(
              chat_id: channel_id,
              text: I18n.t('daily_announcement_header'),
              parse_mode: 'HTML'
            )
            
            events.each_with_index do |event, index|
              message = format_event_with_participants(event)
              buttons = []
              
              if index == events.length - 1
                buttons << [
                  Telegram::Bot::Types::InlineKeyboardButton.new(
                    text: I18n.t('buttons.more'),
                    url: "https://t.me/#{CONFIG['BOT_USERNAME']}"
                  )
                ]
              end
              
              markup = buttons.empty? ? nil : Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: buttons)
              
              @bot.api.send_message(
                chat_id: channel_id,
                text: message,
                parse_mode: 'HTML',
                reply_markup: markup
              )
            end
          end
          
          puts "Daily announcement sent successfully"
        rescue => e
          puts "Error sending daily announcement: #{e.message}"
          puts e.backtrace.join("\n")
        end
      end
      
      def format_event_with_participants(event)
        message = Bot::Helpers::Formatter.event_info(event)
        
        if event.participants.any?
          participants_text = event.participants.map do |participant|
            if participant.nickname
              "@#{participant.nickname}"
            else
              participant.username
            end
          end.join(', ')
          
          message += "\n👥 Участники: #{participants_text}"
        end
        
        message
      end
    end
  end
end