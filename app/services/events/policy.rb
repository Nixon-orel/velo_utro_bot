module Events
  class Policy
    def self.manage?(event:, actor:)
      event && actor && event.author_id == actor.id
    end
  end
end
