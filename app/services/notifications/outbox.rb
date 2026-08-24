module Notifications
  class Outbox
    class << self
      def enqueue!(delivery_attributes, now: AppClock.now)
        NotificationDelivery.transaction do
          delivery_attributes.map do |attributes|
            enqueue_delivery!(attributes, now: now)
          end
        end
      end

      private

      def enqueue_delivery!(attributes, now:)
        idempotency_key = attributes.fetch(:idempotency_key)
        NotificationDelivery.create_or_find_by!(idempotency_key: idempotency_key) do |delivery|
          delivery.assign_attributes(
            event: attributes[:event],
            recipient: attributes[:recipient],
            notification_type: attributes.fetch(:notification_type),
            context_key: attributes.fetch(:context_key),
            operation: attributes.fetch(:operation, 'send_message'),
            chat_id: attributes.fetch(:chat_id).to_s,
            payload: attributes.fetch(:payload),
            status: 'pending',
            attempts: 0,
            next_attempt_at: now
          )
        end
      end
    end
  end
end
