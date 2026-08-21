module Notifications
  class PublishSubscribers
    def self.call(event:, gateway:, payload:)
      sent_count = 0
      failed_user_ids = []

      User.where(subscribed_to_notifications: true).find_each do |subscriber|
        begin
          gateway.send_message(chat_id: subscriber.telegram_id, **payload)
          sent_count += 1
        rescue => e
          failed_user_ids << subscriber.id
          AppLogger.error(
            'Notifications::PublishSubscribers',
            'Failed to notify subscriber',
            event_id: event.id,
            subscriber_id: subscriber.id,
            exception: e
          )
        end
      end

      ServiceResult.success(
        event,
        sent_count: sent_count,
        failed_user_ids: failed_user_ids.freeze
      )
    rescue ActiveRecord::ActiveRecordError => e
      ServiceResult.failure(:subscribers_lookup_failed, error: e, value: event, sent_count: sent_count)
    end
  end
end
