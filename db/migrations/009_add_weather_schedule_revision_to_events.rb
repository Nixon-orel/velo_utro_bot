class AddWeatherScheduleRevisionToEvents < ActiveRecord::Migration[8.0]
  def up
    add_column :events, :weather_schedule_revision, :integer, null: false, default: 0
    add_check_constraint(
      :events,
      'weather_schedule_revision >= 0',
      name: 'events_weather_schedule_revision_check'
    )
  end

  def down
    delivery_count = if table_exists?(:notification_deliveries)
      select_value('SELECT COUNT(*) FROM notification_deliveries').to_i
    else
      0
    end
    revised_event_count = select_value(
      'SELECT COUNT(*) FROM events WHERE weather_schedule_revision <> 0'
    ).to_i
    if delivery_count.positive? || revised_event_count.positive?
      raise ActiveRecord::IrreversibleMigration,
            'weather schedule revisions are in use; keep migrations 009 and 010 applied'
    end

    remove_check_constraint :events, name: 'events_weather_schedule_revision_check'
    remove_column :events, :weather_schedule_revision
  end
end
