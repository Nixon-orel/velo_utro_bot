class AddFinalizedAtToNotificationDeliveries < ActiveRecord::Migration[8.0]
  def up
    add_column :notification_deliveries, :finalized_at, :datetime
    add_index(
      :notification_deliveries,
      [:notification_type, :id],
      where: "status = 'delivered' AND finalized_at IS NULL",
      name: 'index_notification_deliveries_unfinalized'
    )
    add_check_constraint(
      :notification_deliveries,
      "finalized_at IS NULL OR status = 'delivered'",
      name: 'notification_deliveries_finalized_at_check'
    )
  end

  def down
    delivery_count = select_value('SELECT COUNT(*) FROM notification_deliveries').to_i
    revised_event_count = if column_exists?(:events, :weather_schedule_revision)
      select_value('SELECT COUNT(*) FROM events WHERE weather_schedule_revision <> 0').to_i
    else
      0
    end
    if delivery_count.positive? || revised_event_count.positive?
      raise ActiveRecord::IrreversibleMigration,
            'notification delivery context is in use; keep migrations 009 and 010 applied'
    end

    remove_check_constraint(
      :notification_deliveries,
      name: 'notification_deliveries_finalized_at_check'
    )
    remove_index :notification_deliveries, name: 'index_notification_deliveries_unfinalized'
    remove_column :notification_deliveries, :finalized_at
  end
end
