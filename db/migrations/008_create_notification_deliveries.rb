class CreateNotificationDeliveries < ActiveRecord::Migration[8.0]
  def up
    create_table :notification_deliveries do |t|
      t.references :event, null: false, foreign_key: { on_delete: :cascade }
      t.references :recipient, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :notification_type, null: false
      t.string :context_key, null: false
      t.string :idempotency_key, null: false
      t.string :operation, null: false, default: 'send_message'
      t.string :chat_id, null: false
      t.jsonb :payload, null: false, default: {}
      t.string :status, null: false, default: 'pending'
      t.integer :attempts, null: false, default: 0
      t.datetime :next_attempt_at, null: true
      t.datetime :locked_at, null: true
      t.string :lock_token, null: true
      t.datetime :delivered_at, null: true
      t.text :last_error, null: true
      t.jsonb :error_history, null: false, default: []
      t.timestamps
    end

    add_index :notification_deliveries, :idempotency_key, unique: true
    add_index :notification_deliveries, [:status, :next_attempt_at]
    add_index :notification_deliveries, :locked_at, where: "status = 'processing'"
    add_check_constraint(
      :notification_deliveries,
      "status IN ('pending', 'processing', 'delivered', 'failed', 'cancelled')",
      name: 'notification_deliveries_status_check'
    )
    add_check_constraint(
      :notification_deliveries,
      'attempts >= 0',
      name: 'notification_deliveries_attempts_check'
    )
    add_check_constraint(
      :notification_deliveries,
      "operation IN ('send_message', 'edit_message_text')",
      name: 'notification_deliveries_operation_check'
    )
    add_check_constraint(
      :notification_deliveries,
      "jsonb_typeof(payload) = 'object'",
      name: 'notification_deliveries_payload_check'
    )
    add_check_constraint(
      :notification_deliveries,
      "jsonb_typeof(error_history) = 'array'",
      name: 'notification_deliveries_error_history_check'
    )
    add_check_constraint(
      :notification_deliveries,
      <<~SQL.squish,
        (status = 'pending' AND next_attempt_at IS NOT NULL AND locked_at IS NULL AND lock_token IS NULL AND delivered_at IS NULL)
        OR (status = 'processing' AND locked_at IS NOT NULL AND lock_token IS NOT NULL AND delivered_at IS NULL)
        OR (status = 'delivered' AND next_attempt_at IS NULL AND locked_at IS NULL AND lock_token IS NULL AND delivered_at IS NOT NULL)
        OR (status IN ('failed', 'cancelled') AND next_attempt_at IS NULL AND locked_at IS NULL AND lock_token IS NULL AND delivered_at IS NULL)
      SQL
      name: 'notification_deliveries_state_check'
    )
  end

  def down
    delivery_count = select_value('SELECT COUNT(*) FROM notification_deliveries').to_i
    if delivery_count.positive?
      raise ActiveRecord::IrreversibleMigration,
            'notification_deliveries contains data; roll back application code without reverting migration 008'
    end

    drop_table :notification_deliveries
  end
end
