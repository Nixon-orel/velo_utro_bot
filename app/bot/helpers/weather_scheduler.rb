require 'rufus-scheduler'

module Bot
  module Helpers
    class WeatherScheduler
      LOCK_FILE_PATH = '/tmp/velo_utro_bot_weather_scheduler.lock'
      OUTBOX_POLL_INTERVAL = '30s'
      UPDATE_RETRY_DELAY = 5.minutes
      MAX_UPDATE_RETRIES = 3
      MISSED_UPDATE_RECOVERY_DELAY = 1.second
      MISSED_UPDATE_RECOVERY_WINDOW = 1.hour
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
      @outbox_job = nil
      @lock_file = nil

      class << self
        def start(bot = nil)
          return false unless APP_CONFIG.weather_enabled? || weather_outbox_backlog?

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
            schedule_outbox_processing
          end

          restored_count = APP_CONFIG.weather_enabled? ? restore_weather_updates : 0
          process_outbox
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
            @outbox_job = nil
            @notifier = nil
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
          scheduler_status = @mutex.synchronize do
            {
              scheduler_running: @scheduler&.up? || false,
              jobs_count: @jobs.count,
              event_ids: @jobs.keys.map(&:first).uniq.sort,
              outbox_job_active: !@outbox_job.nil?,
              lock_held: lock_held?
            }
          end
          scheduler_status.merge(
            outbox_counts: weather_outbox_counts,
            **weather_failed_delivery_diagnostics
          )
        end

        def schedule_weather_updates(event, bot: nil)
          return false unless APP_CONFIG.weather_enabled?
          return false unless event&.persisted?

          event_datetime = event.starts_at
          unless event.published? && event.weather_data.present? && event_datetime && event_datetime > AppClock.now
            cancel_for(event.id)
            return false
          end

          start(bot) unless @scheduler&.up?
          return false unless @scheduler&.up?

          scheduled_count = @mutex.synchronize do
            cancel_jobs_for(event.id)
            UPDATE_OFFSETS.count do |update_type, offset|
              schedule_update(event, update_type, event_datetime - offset)
            end
          end

          scheduled_count.positive?
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
          !@lock_file.nil? && !@lock_file.closed?
        end

        def restore_weather_updates
          restored_count = 0
          Event.where(published: true).where('date >= ?', AppClock.today).find_each do |event|
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

        def schedule_outbox_processing
          @outbox_job = @scheduler.every(OUTBOX_POLL_INTERVAL) { process_outbox }
        end

        def process_outbox
          @notifier&.process_pending_deliveries
        rescue => e
          AppLogger.error(component, 'Failed to process notification outbox', exception: e)
          []
        end

        def weather_outbox_backlog?
          deliveries = weather_deliveries
          deliveries.where(status: %w[pending processing])
                    .or(deliveries.where(status: 'delivered', finalized_at: nil))
                    .exists?
        end

        def weather_outbox_counts
          counts = weather_deliveries.group(:status).count
          NotificationDelivery::STATUSES.to_h { |status| [status.to_sym, counts.fetch(status, 0)] }
        end

        def weather_failed_delivery_diagnostics
          current_failures = []
          historical_count = 0

          weather_deliveries.where(status: 'failed').includes(:event).find_each do |delivery|
            if WeatherNotifier.delivery_current?(delivery)
              current_failures << delivery
            else
              historical_count += 1
            end
          end

          {
            current_failed_count: current_failures.length,
            historical_failed_count: historical_count,
            failed_event_ids: current_failures.map(&:event_id).uniq.sort,
            oldest_failed_at: current_failures.map(&:updated_at).compact.min
          }
        end

        def weather_deliveries
          NotificationDelivery.where("notification_type LIKE 'weather.%'")
        end

        def schedule_update(event, update_type, update_time, retry_attempt: 0)
          now = AppClock.now
          if update_time <= now
            return false if now - update_time >= MISSED_UPDATE_RECOVERY_WINDOW

            update_time = now + MISSED_UPDATE_RECOVERY_DELAY
          end

          key = [event.id, update_type]
          expected_starts_at = event.starts_at
          job = nil
          job = @scheduler.schedule_at(update_time) do
            begin
              run_update(event.id, update_type, expected_starts_at, job, retry_attempt)
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
          true
        end

        def cancel_jobs_for(event_id)
          keys = @jobs.keys.select { |job_event_id, _| job_event_id == event_id }
          keys.each do |key|
            @jobs.delete(key)&.unschedule
          end
          AppLogger.debug(component, 'Weather jobs cancelled', event_id: event_id, jobs_count: keys.count) if keys.any?
          keys.count
        end

        def run_update(
          event_id,
          update_type,
          expected_starts_at = nil,
          scheduled_job = nil,
          retry_attempt = 0
        )
          AppLogger.info(component, 'Running weather update', event_id: event_id, update_type: update_type)
          event = Event.find_by(id: event_id)
          return :stale unless current_weather_job?(event, update_type, expected_starts_at, scheduled_job)

          result = update_weather(event, update_type, expected_starts_at, scheduled_job)
          schedule_retry(event_id, update_type, expected_starts_at, scheduled_job, retry_attempt) if result == :retry
          result
        rescue => e
          AppLogger.error(
            component,
            'Weather update failed',
            event_id: event_id,
            update_type: update_type,
            exception: e
          )
          schedule_retry(event_id, update_type, expected_starts_at, scheduled_job, retry_attempt)
          :retry
        end

        def update_weather(event, update_type, expected_starts_at = nil, scheduled_job = nil)
          return :completed unless event.latitude && event.longitude

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
            return :retry
          end

          event.reload
          return :stale unless current_weather_job?(event, update_type, expected_starts_at, scheduled_job)

          prepared_update = Event.transaction do
            old_weather = event.weather
            event.update_weather_data(new_weather)
            @notifier.prepare_update(
              event,
              update_type,
              old_weather: old_weather,
              new_weather: new_weather
            )
          end

          begin
            @notifier.deliver_prepared_update(event, prepared_update)
          rescue => e
            AppLogger.error(
              component,
              'Failed to deliver prepared weather update; outbox will retry it',
              event_id: event.id,
              update_type: update_type,
              exception: e
            )
          end

          AppLogger.info(component, 'Weather data updated', event_id: event.id, update_type: update_type)
          :completed
        rescue => e
          AppLogger.error(
            component,
            'Failed to process weather update',
            event_id: event.id,
            update_type: update_type,
            exception: e
          )
          :retry
        end

        def schedule_retry(event_id, update_type, expected_starts_at, scheduled_job, retry_attempt)
          if retry_attempt >= MAX_UPDATE_RETRIES
            AppLogger.error(
              component,
              'Weather update retries exhausted',
              event_id: event_id,
              update_type: update_type,
              attempts: retry_attempt + 1
            )
            return false
          end

          event = Event.find_by(id: event_id)
          event_datetime = event&.starts_at
          return false unless event&.published? && event.weather_data.present?
          return false unless event_datetime && event_datetime > AppClock.now
          return false if expected_starts_at && event_datetime != expected_starts_at

          @mutex.synchronize do
            return false unless @scheduler&.up?

            key = [event.id, update_type]
            current_job = @jobs[key]
            return false if scheduled_job && !current_job.equal?(scheduled_job)

            current_job&.unschedule
            retry_at = AppClock.now + UPDATE_RETRY_DELAY
            scheduled = schedule_update(
              event,
              update_type,
              retry_at,
              retry_attempt: retry_attempt + 1
            )
            if scheduled
              AppLogger.warn(
                component,
                'Weather update retry scheduled',
                event_id: event.id,
                update_type: update_type,
                retry_attempt: retry_attempt + 1,
                retry_at: retry_at
              )
            end
            scheduled
          end
        rescue => e
          AppLogger.error(
            component,
            'Failed to schedule weather update retry',
            event_id: event_id,
            update_type: update_type,
            exception: e
          )
          false
        end

        def current_weather_job?(event, update_type, expected_starts_at, scheduled_job)
          event_datetime = event&.starts_at
          return false unless event&.published? && event.weather_data.present?
          return false unless event_datetime && event_datetime > AppClock.now
          return false if expected_starts_at && event_datetime != expected_starts_at
          return true unless scheduled_job

          @mutex.synchronize { @jobs[[event.id, update_type]].equal?(scheduled_job) }
        end

        def component
          'Bot::Helpers::WeatherScheduler'
        end
      end
    end
  end
end
