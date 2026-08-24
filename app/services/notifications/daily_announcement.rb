module Notifications
  class DailyAnnouncement
    NOTIFICATION_TYPE = 'announcement.daily'.freeze
    ACTIVE_STATUSES = %w[pending processing].freeze
    TERMINAL_STATUSES = %w[failed cancelled].freeze

    class << self
      def last_completed_at
        completed_contexts = deliveries
                             .select(:context_key)
                             .group(:context_key)
                             .having(
                               "COUNT(*) = SUM(CASE WHEN status = 'delivered' THEN 1 ELSE 0 END)"
                             )
        deliveries.where(context_key: completed_contexts).maximum(:finalized_at)
      end

      def backlog?
        unfinished_deliveries.exists?
      end

      def unfinished_context_keys
        unfinished_deliveries.distinct.order(:context_key).pluck(:context_key)
      end

      def status_counts
        counts = deliveries.group(:status).count
        {
          queued: counts.fetch('pending', 0) + counts.fetch('processing', 0),
          failed: counts.fetch('failed', 0)
        }
      end

      def context_key(at)
        at.utc.strftime('%Y-%m-%dT%H:%MZ')
      end

      private

      def deliveries
        NotificationDelivery.where(notification_type: NOTIFICATION_TYPE)
      end

      def unfinished_deliveries
        active = deliveries.where(status: ACTIVE_STATUSES)
        unfinalized = deliveries.where(status: 'delivered', finalized_at: nil)
        active.or(unfinalized)
      end
    end

    def initialize(gateway:)
      @processor = Notifications::OutboxProcessor.new(gateway: gateway)
    end

    def deliver(messages:, channel_id:, at: AppClock.utc_now)
      context_key = self.class.unfinished_context_keys.first || self.class.context_key(at)
      enqueue_batch(messages, channel_id, context_key) unless batch(context_key).exists?
      process_batch(context_key)
      finalize_batch(context_key)
    end

    def process_pending
      self.class.unfinished_context_keys.each do |context_key|
        process_batch(context_key)
        finalize_batch(context_key)
      end
    end

    private

    def enqueue_batch(messages, channel_id, context_key)
      attributes = messages.map do |message|
        {
          notification_type: NOTIFICATION_TYPE,
          context_key: context_key,
          idempotency_key: "announcement:daily:#{context_key}:#{message.fetch(:key)}",
          chat_id: channel_id,
          payload: {
            text: message.fetch(:text),
            parse_mode: 'HTML'
          }
        }
      end
      Notifications::Outbox.enqueue!(attributes)
    end

    def process_batch(context_key)
      batch(context_key).order(:id).each do |delivery|
        next if delivery.status == 'delivered' || TERMINAL_STATUSES.include?(delivery.status)

        @processor.process_due(ids: [delivery.id], limit: 1)
        break if ACTIVE_STATUSES.include?(delivery.reload.status)
      end
    end

    def finalize_batch(context_key)
      deliveries = batch(context_key)
      return false unless deliveries.exists?
      return false if deliveries.where(status: ACTIVE_STATUSES).exists?

      finalized_at = AppClock.now
      deliveries.where(status: 'delivered', finalized_at: nil).update_all(
        finalized_at: finalized_at,
        updated_at: finalized_at
      )
      !deliveries.where(status: TERMINAL_STATUSES).exists?
    end

    def batch(context_key)
      NotificationDelivery.where(
        notification_type: NOTIFICATION_TYPE,
        context_key: context_key
      )
    end
  end
end
