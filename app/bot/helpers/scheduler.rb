require 'rufus-scheduler'

module Bot
  module Helpers
    class Scheduler
      LOCK_FILE_PATH = '/tmp/velo_utro_bot_scheduler.lock'
      LAST_ANNOUNCEMENT_PATH = '/tmp/velo_utro_bot_last_announcement'
      LAST_MONTHLY_STATS_PATH = '/tmp/velo_utro_bot_last_monthly_stats'

      @scheduler = nil
      @daily_job = nil
      @monthly_job = nil
      @cron_expression = nil
      @mutex = Mutex.new
      @lock_file = nil

      class << self
        def start(bot)
          return false unless enabled?

          @mutex.synchronize do
            return true if @scheduler&.up?

            unless acquire_lock
              log(:warn, 'Another scheduler instance holds the lock; startup skipped')
              return false
            end

            @scheduler = Rufus::Scheduler.new
            schedule_daily_announcement(bot) if APP_CONFIG.daily_announcement_enabled?
            schedule_monthly_statistics(bot) if APP_CONFIG.monthly_stats_day
          end

          log(:info, 'Schedulers started')
          true
        rescue => e
          log(:error, 'Failed to start schedulers', exception: e)
          stop
          false
        end

        def stop
          scheduler, lock_file = @mutex.synchronize do
            current_scheduler = @scheduler
            current_lock_file = @lock_file
            @scheduler = nil
            @daily_job = nil
            @monthly_job = nil
            @cron_expression = nil
            @lock_file = nil
            [current_scheduler, current_lock_file]
          end

          begin
            scheduler.shutdown if scheduler&.up?
          ensure
            release_lock(lock_file)
          end
          log(:info, 'Scheduler stopped') if scheduler || lock_file
        end

        def status
          @mutex.synchronize do
            {
              scheduler_running: @scheduler&.up? || false,
              daily_job_active: !@daily_job.nil?,
              monthly_job_active: !@monthly_job.nil?,
              next_run: calculate_next_run(@cron_expression),
              cron_expression: @cron_expression,
              jobs_count: @scheduler&.jobs&.count || 0,
              lock_held: lock_held?
            }
          end
        rescue => e
          log(:error, 'Failed to read scheduler status', exception: e)
          {
            scheduler_running: false,
            daily_job_active: false,
            monthly_job_active: false,
            next_run: nil,
            cron_expression: nil,
            jobs_count: 0,
            lock_held: false
          }
        end

        private

        def enabled?
          APP_CONFIG.daily_announcement_enabled? || APP_CONFIG.monthly_stats_day
        end

        def schedule_daily_announcement(bot)
          time = APP_CONFIG.daily_announcement_time
          hour, minute = time.split(':').map(&:to_i)
          @cron_expression = "#{minute} #{hour} * * * UTC"
          @daily_job = @scheduler.schedule_cron(@cron_expression) { send_daily_announcement(bot) }
          log(:info, 'Daily announcement scheduled', configured_time: time, cron_expression: @cron_expression)
        end

        def schedule_monthly_statistics(bot)
          stats_day = APP_CONFIG.monthly_stats_day
          cron_expression = "0 9 #{stats_day} * * UTC"
          @monthly_job = @scheduler.schedule_cron(cron_expression) { send_monthly_statistics(bot) }
          log(:info, 'Monthly statistics scheduled', day: stats_day, cron_expression: cron_expression)
        end

        def acquire_lock
          @lock_file = File.open(LOCK_FILE_PATH, File::RDWR | File::CREAT, 0o644)
          unless @lock_file.flock(File::LOCK_EX | File::LOCK_NB)
            @lock_file.close
            @lock_file = nil
            return false
          end

          @lock_file.rewind
          @lock_file.truncate(0)
          @lock_file.write(Process.pid.to_s)
          @lock_file.flush
          true
        rescue => e
          log(:error, 'Failed to acquire scheduler lock', exception: e)
          @lock_file&.close
          @lock_file = nil
          false
        end

        def release_lock(lock_file)
          return unless lock_file

          lock_file.flock(File::LOCK_UN)
          lock_file.close
          log(:info, 'Scheduler lock released')
        rescue => e
          log(:error, 'Failed to release scheduler lock', exception: e)
        end

        def send_daily_announcement(bot)
          unless scheduler_lock_alive?
            log(:warn, 'Scheduler lock disappeared; announcement aborted')
            return false
          end

          current_time = AppClock.utc_now
          if recent_announcement?(current_time)
            log(:info, 'Daily announcement skipped because the previous one was recent')
            return false
          end

          channel_id = APP_CONFIG.public_channel_id
          return false if channel_id.to_s.empty?

          events = Event.next_24_hours.select(&:published?)
          send_announcement_messages(bot, channel_id, events)
          File.write(LAST_ANNOUNCEMENT_PATH, current_time.to_i.to_s)
          log(:info, 'Daily announcement sent', events_count: events.count)
          true
        rescue => e
          log(:error, 'Failed to send daily announcement', exception: e)
          false
        end

        def scheduler_lock_alive?
          lock_held?
        end

        def lock_held?
          @lock_file && !@lock_file.closed?
        end

        def recent_announcement?(current_time)
          return false unless File.exist?(LAST_ANNOUNCEMENT_PATH)

          last_time = File.read(LAST_ANNOUNCEMENT_PATH).to_i
          current_time.to_i - last_time < 20.hours
        end

        def send_announcement_messages(bot, channel_id, events)
          if events.empty?
            bot.api.send_message(
              chat_id: channel_id,
              text: I18n.t('daily_announcement_no_events'),
              parse_mode: 'HTML'
            )
            return
          end

          bot.api.send_message(
            chat_id: channel_id,
            text: I18n.t('daily_announcement_header'),
            parse_mode: 'HTML'
          )
          events.each do |event|
            bot.api.send_message(
              chat_id: channel_id,
              text: Bot::Helpers::Formatter.event_info(event),
              parse_mode: 'HTML'
            )
          end
        end

        def send_monthly_statistics(bot)
          previous_month = AppClock.today - 1.month
          stats_period = "#{previous_month.year}-#{previous_month.month}"
          return false if monthly_statistics_sent?(stats_period)

          statistics = Bot::Helpers::Statistics.new(bot)
          unless statistics.send_monthly_report
            log(:warn, 'Monthly statistics were not sent', period: stats_period)
            return false
          end

          File.write(LAST_MONTHLY_STATS_PATH, stats_period)
          log(:info, 'Monthly statistics sent', period: stats_period)
          true
        rescue => e
          log(:error, 'Failed to send monthly statistics', exception: e)
          false
        end

        def monthly_statistics_sent?(stats_period)
          return false unless File.exist?(LAST_MONTHLY_STATS_PATH)

          File.read(LAST_MONTHLY_STATS_PATH).strip == stats_period
        end

        def calculate_next_run(cron_expression)
          return nil unless cron_expression

          minute, hour = cron_expression.split(' ').first(2).map(&:to_i)
          now = AppClock.utc_now
          next_run = Time.utc(now.year, now.month, now.day, hour, minute)
          next_run <= now ? next_run + 1.day : next_run
        end

        def log(level, message, **context)
          AppLogger.public_send(level, 'Bot::Helpers::Scheduler', message, pid: Process.pid, **context)
        end
      end
    end
  end
end
