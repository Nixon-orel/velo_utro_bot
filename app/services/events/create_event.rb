module Events
  class CreateEvent
    SESSION_ATTRIBUTES = {
      'date' => :date,
      'time' => :time,
      'type' => :event_type,
      'location' => :location,
      'distance' => :distance,
      'pace' => :pace,
      'track' => :track,
      'map' => :map,
      'additional_info' => :additional_info,
      'author_id' => :author_id
    }.freeze

    def self.from_session(session:, extra_attributes: {})
      attributes = SESSION_ATTRIBUTES.each_with_object({}) do |(session_key, event_key), result|
        result[event_key] = session.new_event[session_key]
      end
      attributes[:date] = Date.parse(attributes[:date])

      call(attributes: attributes.merge(extra_attributes))
    rescue Date::Error, TypeError => e
      ServiceResult.failure(:invalid_date, error: e)
    end

    def self.call(attributes:)
      event = Event.transaction { Event.create!(attributes) }
      ServiceResult.success(event)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(:validation_failed, error: e, value: e.record)
    rescue ActiveRecord::ActiveRecordError => e
      ServiceResult.failure(:persistence_failed, error: e)
    end
  end
end
