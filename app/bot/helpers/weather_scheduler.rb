require 'rufus-scheduler'

module Bot
  module Helpers
    class WeatherScheduler
      LOCK_FILE_PATH = '/tmp/velo_utro_bot_weather_scheduler.lock'
      UPDATE_OFFSETS = {
        '3d' => 3.days,
        '24h' => 24.hours,
        '2h' => 2.hours
      }.freeze

      @scheduler = nil
      @mutex = Mutex.new
      @jobs = {}
      @bot = nil
      @notifier = nil
      @lock_file = nil

      class << self
        def start(bot = nil)
          return false unless APP_CONFIG.weather_enabled?

          @bot = bot if bot
          unless @bot
            AppLogger.warn(component, 'Scheduler cannot start without Telegram bot')
            return false
          end

          stop

          unless acquire_lock
            AppLogger.warn(component, 'Another weather scheduler instance holds the lock; startup skipped')
            return false
          end

          @mutex.synchronize do
            @notifier = WeatherNotifier.new(@bot)
            @scheduler = Rufus::Scheduler.new
          end

          restored_count = restore_weather_updates
          AppLogger.info(component, 'Scheduler started', at: AppClock.now, restored_events_count: restored_count)
          true
        rescue => e
          AppLogger.error(component, 'Scheduler failed to start', exception: e)
          stop
          false
        end

        def stop
          scheduler, lock_file = @mutex.synchronize do
            current_scheduler = @scheduler
            current_lock_file = @lock_file
            @scheduler = nil
            @jobs = {}
            @lock_file = nil
            [current_scheduler, current_lock_file]
          end
          begin
            scheduler.shutdown if scheduler&.up?
          ensure
            release_lock(lock_file)
          end
          AppLogger.info(component, 'Scheduler stopped', at: AppClock.now) if scheduler || lock_file
        end

        def status
          @mutex.synchronize do
            {
              scheduler_running: @scheduler&.up? || false,
              jobs_count: @jobs.count,
              event_ids: @jobs.keys.map(&:first).uniq.sort,
              lock_held: lock_held?
            }
          end
        end

        def schedule_weather_updates(event)
          return false unless APP_CONFIG.weather_enabled?
          return false unless event&.persisted? && event.weather_data.present?

          start unless @scheduler&.up?
          return false unless @scheduler&.up?

          event_datetime = event.starts_at
          return false unless event_datetime

          @mutex.synchronize do
            cancel_jobs_for(event.id)
            UPDATE_OFFSETS.each do |update_type, offset|
              schedule_update(event, update_type, event_datetime - offset)
            end
          end

          true
        end

        def cancel_for(event_id)
          @mutex.synchronize { cancel_jobs_for(event_id) }
        end

        private

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
          AppLogger.error(component, 'Failed to acquire scheduler lock', exception: e)
          @lock_file&.close
          @lock_file = nil
          false
        end

        def release_lock(lock_file)
          return unless lock_file

          lock_file.flock(File::LOCK_UN)
          lock_file.close
          AppLogger.info(component, 'Scheduler lock released')
        rescue => e
          AppLogger.error(component, 'Failed to release scheduler lock', exception: e)
        end

        def lock_held?
          @lock_file && !@lock_file.closed?
        end

        def restore_weather_updates
          restored_count = 0
          Event.where('date >= ?', AppClock.today).find_each do |event|
            next unless event.weather_data.present?

            restored_count += 1 if schedule_weather_updates(event)
          rescue => e
            AppLogger.error(component, 'Failed to restore event jobs', event_id: event.id, exception: e)
          end
          restored_count
        rescue ActiveRecord::ActiveRecordError => e
          AppLogger.error(component, 'Failed to restore weather jobs from database', exception: e)
          0
        end

        def schedule_update(event, update_type, update_time)
          return if update_time <= AppClock.now

          key = [event.id, update_type]
          job = nil
          job = @scheduler.schedule_at(update_time) do
            begin
              run_update(event.id, update_type)
            ensure
              @mutex.synchronize do
                @jobs.delete(key) if @jobs[key].equal?(job)
              end
            end
          end
          @jobs[key] = job

          AppLogger.info(
            component,
            'Weather update scheduled',
            event_id: event.id,
            update_type: update_type,
            scheduled_at: update_time,
            scheduled_at_utc: update_time.utc
          )
        end

        def cancel_jobs_for(event_id)
          keys = @jobs.keys.select { |job_event_id, _| job_event_id == event_id }
          keys.each do |key|
            @jobs.delete(key)&.unschedule
          end
          AppLogger.debug(component, 'Weather jobs cancelled', event_id: event_id, jobs_count: keys.count) if keys.any?
          keys.count
        end

        def run_update(event_id, update_type)
          AppLogger.info(component, 'Running weather update', event_id: event_id, update_type: update_type)
          event = Event.find_by(id: event_id)
          return unless event

          update_weather(event, update_type)
        rescue => e
          AppLogger.error(
            component,
            'Weather update failed',
            event_id: event_id,
            update_type: update_type,
            exception: e
          )
        end

        def update_weather(event, update_type)
          return unless event.latitude && event.longitude

          coordinates = "#{event.latitude},#{event.longitude}"
          new_weather = WeatherService.fetch_weather_for_event(coordinates, event.date, event.time)
          new_weather ||= WeatherService.get_fallback_weather(event)

          unless new_weather
            AppLogger.warn(
              component,
              'No weather data available; update skipped',
              event_id: event.id,
              update_type: update_type
            )
            return
          end

          old_weather = event.weather
          event.update_weather_data(new_weather)
          notify(event, update_type, old_weather, new_weather)

          AppLogger.info(component, 'Weather data updated', event_id: event.id, update_type: update_type)
        rescue => e
          AppLogger.error(
            component,
            'Failed to process weather update',
            event_id: event.id,
            update_type: update_type,
            exception: e
          )
        end

        def notify(event, update_type, old_weather, new_weather)
          case update_type
          when '3d' then @notifier.handle_3d_weather_update(event, old_weather, new_weather)
          when '24h' then @notifier.handle_24h_weather_update(event, old_weather, new_weather)
          when '2h' then @notifier.handle_2h_weather_update(event, new_weather)
          end
        end

        def component
          'Bot::Helpers::WeatherScheduler'
        end
      end
    end
  end
end
