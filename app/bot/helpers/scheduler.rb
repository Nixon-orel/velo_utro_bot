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
            
            if CONFIG['DAILY_ANNOUNCEMENT_ENABLED']
              time = CONFIG['DAILY_ANNOUNCEMENT_TIME']
              hour, minute = time.split(':').map(&:to_i)
              
              puts "[PID #{Process.pid}] Starting daily announcement scheduler"
              puts "[PID #{Process.pid}] UTC time: #{time}"
              
              cron_expression = "#{minute} #{hour} * * *"
              puts "[PID #{Process.pid}] Cron expression: #{cron_expression}"
              
              @@global_job = @@global_scheduler.cron cron_expression do
                send_daily_announcement(bot)
              end
            end
            
            if ENV['MONTHLY_STATS_DAY']
              stats_day = ENV['MONTHLY_STATS_DAY'].to_i
              stats_day = 28 if stats_day > 28
              stats_day = 1 if stats_day < 1
              
              puts "[PID #{Process.pid}] Starting monthly statistics scheduler for day #{stats_day}"
              
              stats_cron = "0 9 #{stats_day} * *"
              puts "[PID #{Process.pid}] Statistics cron expression: #{stats_cron}"
              
              @@global_scheduler.cron stats_cron do
                send_monthly_statistics(bot)
              end
            end
            
            puts "[PID #{Process.pid}] Scheduler started successfully"
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
          job_active = !@@global_job.nil?
          next_run = nil
          cron_expression = nil
          
          if job_active
            begin
              next_run = @@global_job.next_time if @@global_job.respond_to?(:next_time)
              cron_expression = @@global_job.original if @@global_job.respond_to?(:original)
            rescue => e
              puts "[PID #{Process.pid}] Error getting job status: #{e.message}"
            end
          end
          
          {
            scheduler_running: @@global_scheduler && !@@global_scheduler.down?,
            job_active: job_active,
            next_run: next_run,
            cron_expression: cron_expression,
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
          
          current_time = Time.now.utc
          puts "[#{current_time}] [PID #{Process.pid}] Sending daily announcement..."
          
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
          
          events = Event.next_24_hours.where(published: true)
          
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
      
      def self.send_monthly_statistics(bot)
        begin
          current_time = Time.now.utc
          puts "[#{current_time}] [PID #{Process.pid}] Sending monthly statistics..."
          
          last_stats_file = '/tmp/velo_utro_bot_last_monthly_stats'
          current_month = "#{Date.today.year}-#{Date.today.month}"
          
          if File.exist?(last_stats_file)
            last_stats_month = File.read(last_stats_file).strip
            if last_stats_month == current_month
              puts "[#{current_time}] [PID #{Process.pid}] Statistics for #{current_month} already sent"
              return
            end
          end
          
          statistics = Bot::Helpers::Statistics.new(bot)
          statistics.send_monthly_report
          
          File.write(last_stats_file, current_month)
          
          puts "[#{current_time}] [PID #{Process.pid}] Monthly statistics sent successfully"
        rescue => e
          puts "[#{current_time}] [PID #{Process.pid}] Error sending monthly statistics: #{e.message}"
          puts e.backtrace.join("\n")
        end
      end
    end
  end
end