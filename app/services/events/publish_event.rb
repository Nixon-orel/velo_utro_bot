module Events
  class PublishEvent
    def self.call(event:, actor:, gateway:, channel_id:, payload:)
      return ServiceResult.failure(:forbidden, value: event) unless Policy.manage?(event: event, actor: actor)
      return ServiceResult.failure(:channel_not_configured, value: event) if channel_id.to_s.empty?

      result = nil
      event.with_lock do
        event.reload

        if event.published?
          result = ServiceResult.failure(:already_published, value: event)
          next
        end

        response = gateway.send_message(chat_id: channel_id, **payload)
        message_id = response&.message_id

        if message_id
          event.update!(
            channel_message_id: message_id,
            published: true,
            published_at: AppClock.now
          )
          result = ServiceResult.success(event)
        else
          result = ServiceResult.failure(:invalid_telegram_response, value: event)
        end
      end

      result
    rescue ActiveRecord::ActiveRecordError => e
      ServiceResult.failure(:persistence_failed, error: e, value: event)
    rescue => e
      ServiceResult.failure(:delivery_failed, error: e, value: event)
    end
  end
end
