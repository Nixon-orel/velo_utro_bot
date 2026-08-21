module Events
  class DeleteEvent
    def self.call(event:, actor:)
      return ServiceResult.failure(:forbidden, value: event) unless Policy.manage?(event: event, actor: actor)

      event.author
      participants = event.participants.to_a
      Event.transaction { event.destroy! }

      ServiceResult.success(event, participants: participants)
    rescue ActiveRecord::ActiveRecordError => e
      ServiceResult.failure(:persistence_failed, error: e, value: event)
    end
  end
end
