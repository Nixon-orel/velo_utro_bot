require 'securerandom'

module Events
  class CreateEvent
    CREATION_CLAIM_KEY = 'creation_claim'.freeze
    CREATION_CLAIM_TTL_SECONDS = 120

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

    def self.from_session(session:, extra_attributes: {}, expected_state: nil, &extra_attributes_provider)
      attributes = SESSION_ATTRIBUTES.each_with_object({}) do |(session_key, event_key), result|
        result[event_key] = session.new_event[session_key]
      end
      attributes[:date] = Date.parse(attributes[:date])

      unless expected_state
        provided_attributes = extra_attributes_provider ? extra_attributes_provider.call : extra_attributes
        return call(attributes: attributes.merge(provided_attributes))
      end

      if extra_attributes_provider
        return call_with_claimed_preparation(
          attributes: attributes,
          session: session,
          expected_state: expected_state,
          &extra_attributes_provider
        )
      end

      call_once_from_session(
        attributes: attributes.merge(extra_attributes),
        session: session,
        expected_state: expected_state
      )
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

    def self.call_once_from_session(attributes:, session:, expected_state:)
      event = Event.transaction do
        locked_session = Session.lock.find(session.id)
        next unless locked_session.state == expected_state

        created_event = Event.create!(attributes)
        locked_session.state = nil
        clear_creation_claim(locked_session)
        locked_session.save!
        created_event
      end

      return ServiceResult.failure(:already_processed) unless event

      session.state = nil
      ServiceResult.success(event)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(:validation_failed, error: e, value: e.record)
    rescue ActiveRecord::ActiveRecordError => e
      ServiceResult.failure(:persistence_failed, error: e)
    end
    private_class_method :call_once_from_session

    def self.call_with_claimed_preparation(attributes:, session:, expected_state:)
      claim_token = SecureRandom.uuid
      claim_result = claim_session(
        session: session,
        expected_state: expected_state,
        claim_token: claim_token
      )
      return claim_result if claim_result.failure?

      result = nil
      begin
        provided_attributes = yield
        result = finalize_claimed_session(
          attributes: attributes.merge(provided_attributes),
          session: session,
          expected_state: expected_state,
          claim_token: claim_token
        )
      ensure
        release_session_claim(session: session, claim_token: claim_token) unless result&.success?
      end
      result
    end
    private_class_method :call_with_claimed_preparation

    def self.claim_session(session:, expected_state:, claim_token:)
      now = AppClock.now
      outcome = Session.transaction do
        locked_session = Session.lock.find(session.id)
        next :already_processed unless locked_session.state == expected_state
        next :already_processing if active_creation_claim?(locked_session[CREATION_CLAIM_KEY], now)

        locked_session[CREATION_CLAIM_KEY] = {
          'token' => claim_token,
          'claimed_at' => now.to_f
        }
        locked_session.save!
        :claimed
      end

      return ServiceResult.success if outcome == :claimed

      ServiceResult.failure(outcome)
    rescue ActiveRecord::ActiveRecordError => e
      ServiceResult.failure(:persistence_failed, error: e)
    end
    private_class_method :claim_session

    def self.finalize_claimed_session(attributes:, session:, expected_state:, claim_token:)
      outcome = Event.transaction do
        locked_session = Session.lock.find(session.id)
        next :already_processed unless locked_session.state == expected_state

        claim = locked_session[CREATION_CLAIM_KEY]
        next :claim_lost unless claim.is_a?(Hash) && claim['token'] == claim_token

        event = Event.create!(attributes)
        locked_session.state = nil
        clear_creation_claim(locked_session)
        locked_session.save!
        event
      end

      return ServiceResult.failure(outcome) if outcome.is_a?(Symbol)

      session.state = nil
      ServiceResult.success(outcome)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(:validation_failed, error: e, value: e.record)
    rescue ActiveRecord::ActiveRecordError => e
      ServiceResult.failure(:persistence_failed, error: e)
    end
    private_class_method :finalize_claimed_session

    def self.release_session_claim(session:, claim_token:)
      Session.transaction do
        locked_session = Session.lock.find_by(id: session.id)
        next unless locked_session

        claim = locked_session[CREATION_CLAIM_KEY]
        next unless claim.is_a?(Hash) && claim['token'] == claim_token

        clear_creation_claim(locked_session)
        locked_session.save!
      end
    rescue ActiveRecord::ActiveRecordError => e
      AppLogger.error('Events::CreateEvent', 'Failed to release creation claim', session_id: session.id, exception: e)
    end
    private_class_method :release_session_claim

    def self.active_creation_claim?(claim, now)
      return false unless claim.is_a?(Hash) && claim['token'].present?

      claim['claimed_at'].to_f > now.to_f - CREATION_CLAIM_TTL_SECONDS
    end
    private_class_method :active_creation_claim?

    def self.clear_creation_claim(session)
      data = session.data.is_a?(Hash) ? session.data.dup : {}
      data.delete(CREATION_CLAIM_KEY)
      session.data = data
    end
    private_class_method :clear_creation_claim
  end
end
