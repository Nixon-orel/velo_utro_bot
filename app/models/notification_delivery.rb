require 'securerandom'

class NotificationDelivery < ActiveRecord::Base
  class LostLease < StandardError; end

  STATUSES = %w[pending processing delivered failed cancelled].freeze
  OPERATIONS = %w[send_message edit_message_text].freeze
  PROCESSING_LEASE = 5.minutes
  MAX_ATTEMPTS = 5
  RETRY_DELAYS = [30.seconds, 2.minutes, 10.minutes, 30.minutes].freeze
  EVENT_OPTIONAL_NOTIFICATION_TYPES = ['announcement.daily'].freeze

  belongs_to :event, optional: true
  belongs_to :recipient, class_name: 'User', optional: true

  validates :notification_type, :context_key, :idempotency_key, :chat_id, presence: true
  validates :event, presence: true, unless: :event_optional?
  validates :status, inclusion: { in: STATUSES }
  validates :operation, inclusion: { in: OPERATIONS }
  validates :attempts, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :payload_is_an_object
  validate :state_timestamps_are_consistent

  class << self
    def claim_due(now: AppClock.now, limit: 100, ids: nil, notification_type_prefix: nil)
      transaction do
        pending = where(status: 'pending').where('next_attempt_at <= ?', now)
        stale = where(status: 'processing').where('locked_at <= ?', now - PROCESSING_LEASE)
        scope = pending.or(stale)
        scope = scope.where(id: ids) if ids
        if notification_type_prefix
          scope = scope.where('notification_type LIKE ?', "#{notification_type_prefix}%")
        end

        deliveries = scope.order(:next_attempt_at, :id).limit(limit).lock('FOR UPDATE SKIP LOCKED').to_a
        deliveries.each do |delivery|
          delivery.update_columns(
            status: 'processing',
            locked_at: now,
            lock_token: SecureRandom.uuid,
            updated_at: now
          )
        end
        deliveries
      end
    end
  end

  def mark_delivered!(now: AppClock.now)
    update_with_lease!(
      status: 'delivered',
      attempts: attempts + 1,
      delivered_at: now,
      next_attempt_at: nil,
      locked_at: nil,
      lock_token: nil,
      last_error: nil
    )
  end

  def mark_cancelled!
    update_with_lease!(
      status: 'cancelled',
      next_attempt_at: nil,
      locked_at: nil,
      lock_token: nil,
      delivered_at: nil,
      last_error: nil
    )
  end

  def record_failure!(error, now: AppClock.now)
    attempt_number = attempts + 1
    error_class = error.class.name
    error_message = filtered_error_message(error).slice(0, 1_000)
    history = error_history.to_a + [
      {
        'at' => now.iso8601,
        'error_class' => error_class,
        'message' => error_message
      }
    ]
    attributes = {
      attempts: attempt_number,
      locked_at: nil,
      lock_token: nil,
      last_error: "#{error_class}: #{error_message}",
      error_history: history
    }

    if attempt_number >= MAX_ATTEMPTS
      attributes.merge!(
        status: 'failed',
        next_attempt_at: nil
      )
    else
      attributes.merge!(
        status: 'pending',
        next_attempt_at: now + RETRY_DELAYS.fetch(attempt_number - 1)
      )
    end

    update_with_lease!(attributes)
  end

  private

  def payload_is_an_object
    errors.add(:payload, 'must be an object') unless payload.is_a?(Hash)
  end

  def event_optional?
    EVENT_OPTIONAL_NOTIFICATION_TYPES.include?(notification_type)
  end

  def state_timestamps_are_consistent
    valid = case status
    when 'pending'
      next_attempt_at.present? && locked_at.nil? && lock_token.nil? &&
        delivered_at.nil? && finalized_at.nil?
    when 'processing'
      locked_at.present? && lock_token.present? && delivered_at.nil? && finalized_at.nil?
    when 'delivered'
      next_attempt_at.nil? && locked_at.nil? && lock_token.nil? && delivered_at.present?
    when 'failed', 'cancelled'
      next_attempt_at.nil? && locked_at.nil? && lock_token.nil? &&
        delivered_at.nil? && finalized_at.nil?
    else
      false
    end
    errors.add(:status, 'has inconsistent timestamps') unless valid
  end

  def filtered_error_message(error)
    secrets = [APP_CONFIG.telegram_token, APP_CONFIG.weather_api_key]
              .map(&:to_s)
              .reject(&:empty?)
    secrets.reduce(error.message.to_s.dup) do |message, secret|
      message.gsub(secret, '[FILTERED]')
    end
  end

  def update_with_lease!(attributes)
    token = lock_token
    updated_count = self.class.where(
      id: id,
      status: 'processing',
      lock_token: token
    ).update_all(attributes.merge(updated_at: AppClock.now))
    raise LostLease, "delivery #{id} processing lease was replaced" unless updated_count == 1

    reload
  end
end
