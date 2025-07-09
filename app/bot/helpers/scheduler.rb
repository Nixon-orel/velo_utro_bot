require 'rufus-scheduler'

module Bot
  module Helpers
    class Scheduler
      @@global_scheduler = nil
      @@global_job = nil
      @@mutex = Mutex.new
      @@lock_file = nil
      LOCK_FILE_PATH = '/tmp/velo_utro_bot_scheduler.lock'
      
      def self.start(bot)
        return unless CONFIG['DAILY_ANNOUNCEMENT_ENABLED']
        
        @@mutex.synchronize do
          if acquire_lock
            stop_internal
            
            @@global_scheduler = Rufus::Scheduler.new
            
            time = CONFIG['DAILY_ANNOUNCEMENT_TIME']
            timezone = CONFIG['TIMEZONE'] || 'Europe/Moscow'
            
            moscow_time = Time.parse("#{time} #{timezone}")
            utc_time = moscow_time.utc
            utc_hour = utc_time.hour
            utc_minute = utc_time.min
            
            puts "[PID #{Process.pid}] Starting daily announcement scheduler"
            puts "[PID #{Process.pid}] Moscow time: #{time} (#{timezone})"
            puts "[PID #{Process.pid}] UTC time: #{utc_hour}:#{utc_minute.to_s.rjust(2, '0')} (UTC)"
            puts "[PID #{Process.pid}] Cron expression: #{utc_minute} #{utc_hour} * * * (UTC)"
            
            @@global_job = @@global_scheduler.cron "#{utc_minute} #{utc_hour} * * *" do
              send_daily_announcement(bot)
            end
            
            puts "[PID #{Process.pid}] Daily announcement scheduler started successfully"
          else
            puts "[PID #{Process.pid}] Another scheduler instance is already running, skipping..."
          end
        end
      end
      
      def self.stop
        stop_internal
        release_lock
      end
      
      def self.status
        @@mutex.synchronize do
          job_active = @@global_job && @@global_job.respond_to?(:next_time)
          
          {
            scheduler_running: @@global_scheduler && !@@global_scheduler.down?,
            job_active: job_active,
            next_run: job_active ? @@global_job.next_time : nil,
            cron_expression: job_active ? @@global_job.original : nil,
            jobs_count: @@global_scheduler&.jobs&.count || 0,
            lock_file_exists: File.exist?(LOCK_FILE_PATH)
          }
        end
      end
      
      private
      
      def self.stop_internal
        if @@global_job
          if @@global_job.respond_to?(:unschedule)
            @@global_job.unschedule
            puts "[PID #{Process.pid}] Scheduled job unscheduled"
          else
            puts "[PID #{Process.pid}] Job object is not valid (#{@@global_job.class}): #{@@global_job}"
          end
          @@global_job = nil
        end
        
        if @@global_scheduler && !@@global_scheduler.down?
          @@global_scheduler.shutdown
          @@global_scheduler = nil
          puts "[PID #{Process.pid}] Scheduler stopped"
        end
      end
      
      def self.acquire_lock
        begin
          @@lock_file = File.open(LOCK_FILE_PATH, File::RDWR | File::CREAT, 0644)
          if @@lock_file.flock(File::LOCK_EX | File::LOCK_NB)
            @@lock_file.write(Process.pid.to_s)
            @@lock_file.flush
            true
          else
            @@lock_file.close
            @@lock_file = nil
            false
          end
        rescue => e
          puts "[PID #{Process.pid}] Error acquiring lock: #{e.message}"
          false
        end
      end
      
      def self.release_lock
        if @@lock_file
          @@lock_file.flock(File::LOCK_UN)
          @@lock_file.close
          File.delete(LOCK_FILE_PATH) if File.exist?(LOCK_FILE_PATH)
          @@lock_file = nil
          puts "[PID #{Process.pid}] Lock released"
        end
      end
      
      def self.parse_time(time_string)
        hour, minute = time_string.split(':').map(&:to_i)
        "#{minute} #{hour}"
      end
      
      def self.send_daily_announcement(bot)
        begin
          return unless @@lock_file
          
          unless File.exist?(LOCK_FILE_PATH)
            puts "[PID #{Process.pid}] Lock file disappeared, aborting announcement"
            return
          end
          
          current_time = Time.now.in_time_zone(CONFIG['TIMEZONE'] || 'Europe/Moscow')
          utc_time = Time.now.utc
          puts "[#{current_time}] [PID #{Process.pid}] Sending daily announcement..."
          puts "[#{utc_time}] [PID #{Process.pid}] UTC time for reference"
          
          last_announcement_file = '/tmp/velo_utro_bot_last_announcement'
          if File.exist?(last_announcement_file)
            last_announcement_time = File.read(last_announcement_file).to_i
            time_since_last = current_time.to_i - last_announcement_time
            
            if time_since_last < 20 * 3600
              puts "[#{current_time}] [PID #{Process.pid}] Skipping announcement - too soon since last one"
              puts "[#{current_time}] [PID #{Process.pid}] Time since last: #{time_since_last}s (#{(time_since_last/3600.0).round(2)} hours)"
              return
            end
          end
          
          configured_time = CONFIG['DAILY_ANNOUNCEMENT_TIME'] || '08:00'
          configured_hour, configured_minute = configured_time.split(':').map(&:to_i)
          
          moscow_hour = current_time.hour
          moscow_minute = current_time.min
          
          expected_minutes = configured_hour * 60 + configured_minute
          actual_minutes = moscow_hour * 60 + moscow_minute
          time_diff_minutes = (actual_minutes - expected_minutes).abs
          
          if time_diff_minutes > 5
            puts "[#{current_time}] [PID #{Process.pid}] Skipping announcement - wrong time"
            puts "[#{current_time}] [PID #{Process.pid}] Expected: #{configured_time} Moscow, Actual: #{moscow_hour}:#{moscow_minute.to_s.rjust(2, '0')} Moscow"
            puts "[#{current_time}] [PID #{Process.pid}] Time difference: #{time_diff_minutes} minutes"
            return
          end
          
          events = Event.next_24_hours
          
          channel_id = CONFIG['PUBLIC_CHANNEL_ID']
          return unless channel_id
          
          if events.empty?
            bot.api.send_message(
              chat_id: channel_id,
              text: I18n.t('daily_announcement_no_events'),
              parse_mode: 'HTML'
            )
          else
            bot.api.send_message(
              chat_id: channel_id,
              text: I18n.t('daily_announcement_header'),
              parse_mode: 'HTML'
            )
            
            events.each do |event|
              message = Bot::Helpers::Formatter.event_info(event)
              
              bot.api.send_message(
                chat_id: channel_id,
                text: message,
                parse_mode: 'HTML'
              )
            end
          end
          
          File.write(last_announcement_file, current_time.to_i.to_s)
          
          puts "[#{current_time}] [PID #{Process.pid}] Daily announcement sent successfully"
        rescue => e
          current_time = Time.now.in_time_zone(CONFIG['TIMEZONE'] || 'Europe/Moscow')
          puts "[#{current_time}] [PID #{Process.pid}] Error sending daily announcement: #{e.message}"
          puts e.backtrace.join("\n")
        end
      end
    end
  end
end