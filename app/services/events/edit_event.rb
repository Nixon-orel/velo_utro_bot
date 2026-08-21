module Events
  class EditEvent
    EDITABLE_FIELDS = %i[
      date
      time
      location
      track
      map
      additional_info
      weather_city
      latitude
      longitude
      weather_data
      weather_updated_at
    ].freeze

    def self.call(event:, actor:, changes:)
      return ServiceResult.failure(:forbidden, value: event) unless Policy.manage?(event: event, actor: actor)

      normalized_changes = changes.transform_keys(&:to_sym).slice(*EDITABLE_FIELDS)
      return ServiceResult.failure(:invalid_changes, value: event) if normalized_changes.empty?

      previous_values = normalized_changes.keys.to_h { |field| [field, event.public_send(field)] }
      Event.transaction { event.update!(normalized_changes) }

      ServiceResult.success(event, previous_values: previous_values, changed_fields: event.previous_changes.keys.map(&:to_sym))
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(:validation_failed, error: e, value: event)
    rescue ActiveRecord::ActiveRecordError => e
      ServiceResult.failure(:persistence_failed, error: e, value: event)
    end
  end
end
