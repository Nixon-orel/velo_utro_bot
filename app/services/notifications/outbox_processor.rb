module Notifications
  class OutboxProcessor
    def initialize(gateway:, delivery_guard: nil, notification_type_prefix: nil)
      @gateway = gateway
      @delivery_guard = delivery_guard || ->(_delivery) { true }
      @notification_type_prefix = notification_type_prefix
    end

    def process_due(limit: 100, ids: nil)
      processed = []
      limit.times do
        now = AppClock.now
        delivery = NotificationDelivery.claim_due(
          now: now,
          limit: 1,
          ids: ids,
          notification_type_prefix: @notification_type_prefix
        ).first
        break unless delivery

        process_delivery(delivery, now: now)
        processed << delivery
      end
      processed
    end

    private

    def process_delivery(delivery, now:)
      unless @delivery_guard.call(delivery)
        delivery.mark_cancelled!
        log(:info, 'Notification delivery cancelled', delivery: delivery)
        return
      end

      payload = delivery.payload.deep_symbolize_keys.except(:chat_id)
      @gateway.public_send(delivery.operation, **payload, chat_id: delivery.chat_id)
      delivery.mark_delivered!(now: now)
      log(:info, 'Notification delivered', delivery: delivery)
    rescue NotificationDelivery::LostLease => e
      log(:warn, 'Notification delivery lease was replaced', delivery: delivery, error: e.message)
    rescue => e
      record_failure(delivery, e, now: now)
    end

    def record_failure(delivery, error, now:)
      delivery.record_failure!(error, now: now)
      log(:error, 'Notification delivery failed', delivery: delivery, error: delivery.last_error)
    rescue NotificationDelivery::LostLease => e
      log(
        :warn,
        'Notification delivery lease was replaced before failure was recorded',
        delivery: delivery,
        error: e.message
      )
    end

    def log(level, message, delivery:, **context)
      AppLogger.public_send(
        level,
        'Notifications::OutboxProcessor',
        message,
        delivery_id: delivery.id,
        notification_type: delivery.notification_type,
        attempts: delivery.attempts,
        **context
      )
    end
  end
end
