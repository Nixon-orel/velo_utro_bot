require 'rufus-scheduler'

module Bot
  module Helpers
    class Scheduler
      @@instance = nil
      @@mutex = Mutex.new
      
      def self.instance(bot)
        @@mutex.synchronize do
          @@instance ||= new(bot)
        end
      end
      
      def initialize(bot)
        @bot = bot
        @scheduler = nil
        @job = nil
      end
      
      def start
        return unless CONFIG['DAILY_ANNOUNCEMENT_ENABLED']
        
        @@mutex.synchronize do
          stop
          
          @scheduler = Rufus::Scheduler.new
          
          time = CONFIG['DAILY_ANNOUNCEMENT_TIME']
          timezone = CONFIG['TIMEZONE'] || 'Europe/Moscow'
          puts "Starting daily announcement scheduler at #{time} (#{timezone})"
          
          @job = @scheduler.cron "0 #{parse_time(time)} * * *", timezone: timezone do
            send_daily_announcement
          end
          
          puts "Daily announcement scheduler started successfully"
        end
      end
      
      def stop
        @@mutex.synchronize do
          if @job
            @job.unschedule
            @job = nil
            puts "Scheduled job unscheduled"
          end
          
          if @scheduler && !@scheduler.down?
            @scheduler.shutdown
            @scheduler = nil
            puts "Scheduler stopped"
          end
        end
      end
      
      private
      
      def parse_time(time_string)
        hour, minute = time_string.split(':').map(&:to_i)
        "#{minute} #{hour}"
      end
      
      def send_daily_announcement
        begin
          current_time = Time.now.in_time_zone(CONFIG['TIMEZONE'] || 'Europe/Moscow')
          puts "[#{current_time}] Sending daily announcement..."
          
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
            
            events.each do |event|
              message = Bot::Helpers::Formatter.event_info(event)
              
              response = @bot.api.send_message(
                chat_id: channel_id,
                text: message,
                parse_mode: 'HTML'
              )
              
              if response.dig('result', 'message_id') && !event.channel_message_id
                event.update(channel_message_id: response.dig('result', 'message_id'))
              end
            end
          end
          
          puts "[#{current_time}] Daily announcement sent successfully"
        rescue => e
          current_time = Time.now.in_time_zone(CONFIG['TIMEZONE'] || 'Europe/Moscow')
          puts "[#{current_time}] Error sending daily announcement: #{e.message}"
          puts e.backtrace.join("\n")
        end
      end
      
    end
  end
end