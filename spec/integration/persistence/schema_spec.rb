require 'integration_helper'
require_relative '../../../db/migrations/008_create_notification_deliveries'
require_relative '../../../db/migrations/009_add_weather_schedule_revision_to_events'
require_relative '../../../db/migrations/010_add_finalized_at_to_notification_deliveries'

RSpec.describe 'test database schema' do
  it 'is current and exposes all migrated persistence columns' do
    migration_context = ActiveRecord::MigrationContext.new(
      File.join(VELO_UTRO_ROOT, 'db', 'migrations')
    )

    expect(migration_context.needs_migration?).to be(false)
    expect(Event.column_names).to include(
      'published',
      'published_at',
      'weather_data',
      'weather_schedule_revision'
    )
    expect(NotificationDelivery.column_names).to include(
      'event_id',
      'recipient_id',
      'notification_type',
      'context_key',
      'idempotency_key',
      'operation',
      'chat_id',
      'payload',
      'status',
      'attempts',
      'next_attempt_at',
      'locked_at',
      'lock_token',
      'delivered_at',
      'finalized_at',
      'last_error',
      'error_history'
    )
  end

  it 'keeps the checked-in schema dump synchronized with context migrations' do
    migration_context = ActiveRecord::MigrationContext.new(
      File.join(VELO_UTRO_ROOT, 'db', 'migrations')
    )
    schema = File.read(File.join(VELO_UTRO_ROOT, 'db', 'schema.rb'))

    expect(schema).to include("define(version: #{migration_context.current_version})")
    expect(schema).to include(
      't.integer "weather_schedule_revision", default: 0, null: false',
      't.datetime "finalized_at"',
      'name: "index_notification_deliveries_unfinalized"',
      'name: "notification_deliveries_finalized_at_check"'
    )
  end

  it 'enforces unique notification delivery idempotency keys' do
    author = create_user(telegram_id: 1)
    event = create_event(author: author)
    attributes = {
      event_id: event.id,
      recipient_id: author.id,
      notification_type: 'weather.critical_24h',
      context_key: 'event-context',
      idempotency_key: "weather:#{event.id}:critical_24h:user:#{author.id}",
      chat_id: author.telegram_id,
      payload: { text: 'Weather changed', parse_mode: 'HTML' },
      status: 'pending',
      attempts: 0,
      next_attempt_at: AppClock.now,
      created_at: AppClock.now,
      updated_at: AppClock.now
    }
    NotificationDelivery.insert!(attributes)

    expect { NotificationDelivery.insert!(attributes) }
      .to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'rejects invalid notification delivery state at the database boundary' do
    author = create_user(telegram_id: 1)
    event = create_event(author: author)

    expect do
      NotificationDelivery.insert!({
        event_id: event.id,
        notification_type: 'weather.critical_24h',
        context_key: 'event-context',
        idempotency_key: "weather:#{event.id}:invalid-state",
        chat_id: author.telegram_id,
        payload: { text: 'Weather changed' },
        status: 'unknown',
        attempts: 0,
        next_attempt_at: AppClock.now,
        created_at: AppClock.now,
        updated_at: AppClock.now
      })
    end.to raise_error(ActiveRecord::StatementInvalid)
  end

  it 'rejects a pending delivery without a retry timestamp at the database boundary' do
    author = create_user(telegram_id: 1)
    event = create_event(author: author)

    expect do
      NotificationDelivery.insert!({
        event_id: event.id,
        notification_type: 'weather.critical_24h',
        context_key: 'event-context',
        idempotency_key: "weather:#{event.id}:missing-next-at",
        chat_id: author.telegram_id,
        payload: { text: 'Weather changed' },
        status: 'pending',
        attempts: 0,
        next_attempt_at: nil,
        created_at: AppClock.now,
        updated_at: AppClock.now
      })
    end.to raise_error(ActiveRecord::StatementInvalid)
  end

  it 'rejects a negative weather schedule revision at the database boundary' do
    event = create_event(author: create_user(telegram_id: 1))

    expect { event.update_column(:weather_schedule_revision, -1) }
      .to raise_error(ActiveRecord::StatementInvalid)
  end

  it 'rejects finalization timestamps on undelivered records at the database boundary' do
    author = create_user(telegram_id: 1)
    event = create_event(author: author)

    expect do
      NotificationDelivery.insert!({
        event_id: event.id,
        notification_type: 'weather.critical_24h',
        context_key: 'event-context',
        idempotency_key: "weather:#{event.id}:invalid-finalization",
        chat_id: author.telegram_id,
        payload: { text: 'Weather changed' },
        status: 'pending',
        attempts: 0,
        next_attempt_at: AppClock.now,
        finalized_at: AppClock.now,
        created_at: AppClock.now,
        updated_at: AppClock.now
      })
    end.to raise_error(ActiveRecord::StatementInvalid)
  end

  it 'refuses to roll back a non-empty notification outbox' do
    author = create_user(telegram_id: 1)
    event = create_event(author: author)
    NotificationDelivery.create!(
      event: event,
      notification_type: 'weather.critical_24h',
      context_key: 'event-context',
      idempotency_key: "weather:#{event.id}:rollback-guard",
      chat_id: author.telegram_id,
      payload: { text: 'Weather changed' },
      status: 'pending',
      attempts: 0,
      next_attempt_at: AppClock.now
    )

    expect { CreateNotificationDeliveries.new.down }
      .to raise_error(ActiveRecord::IrreversibleMigration)
  end

  it 'stops a multi-step rollback before dropping outbox context columns' do
    author = create_user(telegram_id: 1)
    event = create_event(author: author)
    NotificationDelivery.create!(
      event: event,
      notification_type: 'weather.critical_24h',
      context_key: 'event-context',
      idempotency_key: "weather:#{event.id}:rollback-context-guard",
      chat_id: author.telegram_id,
      payload: { text: 'Weather changed' },
      status: 'pending',
      attempts: 0,
      next_attempt_at: AppClock.now
    )

    expect { AddFinalizedAtToNotificationDeliveries.new.down }
      .to raise_error(ActiveRecord::IrreversibleMigration)
    expect { AddWeatherScheduleRevisionToEvents.new.down }
      .to raise_error(ActiveRecord::IrreversibleMigration)
    expect(NotificationDelivery.column_names).to include('finalized_at')
    expect(Event.column_names).to include('weather_schedule_revision')
  end

  it 'keeps both context migrations applied while an event revision is in use' do
    event = create_event(author: create_user(telegram_id: 1))
    event.update!(date: event.date + 1.day)

    expect(NotificationDelivery.where(event: event)).to be_empty
    expect { AddFinalizedAtToNotificationDeliveries.new.down }
      .to raise_error(ActiveRecord::IrreversibleMigration)
    expect { AddWeatherScheduleRevisionToEvents.new.down }
      .to raise_error(ActiveRecord::IrreversibleMigration)
    expect(NotificationDelivery.column_names).to include('finalized_at')
    expect(Event.column_names).to include('weather_schedule_revision')
  end

  it 'enforces unique Telegram user ids in PostgreSQL' do
    create_user(telegram_id: 1)

    expect do
      User.insert!(
        {
          telegram_id: '1',
          username: 'Duplicate',
          created_at: Time.now,
          updated_at: Time.now
        }
      )
    end.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'enforces unique event participants in PostgreSQL' do
    author = create_user(telegram_id: 1)
    participant = create_user(telegram_id: 2)
    event = create_event(author: author)
    event.participants << participant

    expect do
      ActiveRecord::Base.connection.execute(
        ActiveRecord::Base.sanitize_sql_array(
          [
            'INSERT INTO participants (event_id, user_id, created_at, updated_at) VALUES (?, ?, ?, ?)',
            event.id,
            participant.id,
            Time.now,
            Time.now
          ]
        )
      )
    end.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
