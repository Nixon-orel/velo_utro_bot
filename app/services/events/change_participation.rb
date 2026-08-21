module Events
  class ChangeParticipation
    def self.call(event:, actor:, join:)
      return ServiceResult.failure(:invalid_actor, value: event) unless actor

      changed = false
      Event.transaction do
        participating = event.participants.exists?(actor.id)

        if join && !participating
          event.participants << actor
          changed = true
        elsif !join && participating
          event.participants.delete(actor)
          changed = true
        end
      end

      ServiceResult.success(event, changed: changed, participating: join)
    rescue ActiveRecord::RecordNotUnique
      event.participants.reset
      ServiceResult.success(event, changed: false, participating: true)
    rescue ActiveRecord::ActiveRecordError => e
      ServiceResult.failure(:persistence_failed, error: e, value: event)
    end
  end
end
