class MakeEventOptionalOnNotificationDeliveries < ActiveRecord::Migration[8.0]
  def up
    change_column_null :notification_deliveries, :event_id, true
  end

  def down
    without_event = select_value(
      'SELECT COUNT(*) FROM notification_deliveries WHERE event_id IS NULL'
    ).to_i
    if without_event.positive?
      raise ActiveRecord::IrreversibleMigration,
            'notification_deliveries without events exist; keep migration 011 applied'
    end

    change_column_null :notification_deliveries, :event_id, false
  end
end
