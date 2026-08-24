require 'integration_helper'

RSpec.describe Bot::Helpers::WeatherNotifier do
  before do
    use_app_config('PUBLIC_CHANNEL_ID' => '@veloutro')
    AppClock.source = -> { Time.utc(2026, 8, 22, 9, 0) }
  end

  it 'updates the existing channel message silently for a non-critical change' do
    author = create_user(telegram_id: 1)
    event = create_event(
      author: author,
      published: true,
      channel_message_id: 42,
      weather_data: weather(temp: 11)
    )
    bot, api = recording_bot

    described_class.new(bot).handle_24h_weather_update(event, weather(temp: 10), weather(temp: 11))

    expect(api.sent_messages).to be_empty
    expect(api.edited_messages.last).to include(
      chat_id: '@veloutro',
      message_id: 42,
      parse_mode: 'HTML'
    )
    expect(NotificationDelivery.last.reload.finalized_at).to eq(AppClock.now)
  end

  it 'does not publish a two-hour forecast for a draft event' do
    author = create_user(telegram_id: 1)
    event = create_event(author: author, published: false)
    bot, api = recording_bot

    described_class.new(bot).handle_2h_weather_update(event, weather(temp: 15))

    expect(api.sent_messages).to be_empty
    expect(event.reload.weather_alerts_sent).not_to have_key('2h_channel')
  end

  it 'publishes a two-hour forecast for a published event and records delivery' do
    AppClock.source = -> { Time.zone.local(2026, 8, 24, 7, 0) }
    author = create_user(telegram_id: 1)
    event = create_event(
      author: author,
      date: Date.new(2026, 8, 24),
      time: '09:00',
      published: true
    )
    bot, api = recording_bot

    described_class.new(bot).handle_2h_weather_update(event, weather(temp: 15))

    expect(api.sent_messages).to contain_exactly(
      include(
        chat_id: '@veloutro',
        text: include('🚴‍♀️ Велосипед', 'Ясно, 15°C'),
        parse_mode: 'HTML'
      )
    )
    expect(event.reload.weather_alerts_sent).to include(
      '2h_channel' => AppClock.now.to_s
    )
  end

  it 'does not publish the same successful two-hour forecast twice' do
    author = create_user(telegram_id: 1)
    event = create_event(author: author, published: true)
    bot, api = recording_bot
    notifier = described_class.new(bot)

    notifier.handle_2h_weather_update(event, weather(temp: 15))
    notifier.handle_2h_weather_update(event, weather(temp: 15))

    expect(api.sent_messages.map { |payload| payload[:chat_id] }).to eq(['@veloutro'])
  end

  it 'does not mark a two-hour channel forecast after Telegram delivery fails' do
    author = create_user(telegram_id: 1)
    event = create_event(author: author, published: true)
    bot, api = recording_bot(send_errors: [Faraday::TimeoutError.new('timeout')])

    described_class.new(bot).handle_2h_weather_update(event, weather(temp: 15))

    expect(api.sent_messages.map { |payload| payload[:chat_id] }).to eq(['@veloutro'])
    expect(event.reload.weather_alerts_sent).not_to have_key('2h_channel')
    expect(NotificationDelivery.last).to have_attributes(
      event_id: event.id,
      notification_type: 'weather.2h_channel',
      chat_id: '@veloutro',
      status: 'pending',
      attempts: 1
    )
  end

  it 'cancels a failed two-hour forecast after its event payload changes' do
    AppClock.source = -> { Time.zone.local(2026, 8, 24, 7, 0) }
    author = create_user(telegram_id: 1)
    event = create_event(
      author: author,
      date: Date.new(2026, 8, 24),
      time: '09:00',
      published: true,
      weather_data: weather(temp: 15)
    )
    bot, api = recording_bot(send_errors: [Faraday::TimeoutError.new('timeout')])
    notifier = described_class.new(bot)

    notifier.handle_2h_weather_update(event, weather(temp: 15))
    event.update!(location: 'Новое место')
    AppClock.source = -> { Time.zone.local(2026, 8, 24, 7, 0, 30) }
    notifier.process_pending_deliveries

    expect(api.sent_messages.length).to eq(1)
    expect(NotificationDelivery.last.reload.status).to eq('cancelled')
    expect(event.reload.weather_alerts_sent).not_to have_key('2h_channel')
  end

  it 'does not mark a critical alert as sent when every user delivery fails' do
    author = create_user(telegram_id: 1)
    event = create_event(author: author, published: true)
    bot, api = recording_bot(send_errors: [Faraday::TimeoutError.new('timeout')])

    described_class.new(bot).handle_24h_weather_update(event, weather(temp: 10), weather(temp: 20))

    expect(api.sent_messages.map { |payload| payload[:chat_id] }).to eq([author.telegram_id])
    expect(event.reload.weather_alerts_sent).not_to have_key('critical_24h')
  end

  it 'does not mark a critical stage after only some recipients receive it' do
    author = create_user(telegram_id: 1)
    participant = create_user(telegram_id: 2)
    event = create_event(author: author, published: true)
    event.participants << participant
    bot, api = recording_bot(send_errors: [Faraday::TimeoutError.new('timeout')])

    described_class.new(bot).handle_3d_weather_update(event, weather(temp: 10), weather(temp: 20))

    expect(api.sent_messages.map { |payload| payload[:chat_id] }).to eq(
      [author.telegram_id, participant.telegram_id]
    )
    expect(event.reload.weather_alerts_sent).not_to have_key('critical_3d')
  end

  it 'persists a partial critical delivery and retries only the failed recipient' do
    AppClock.source = -> { Time.utc(2026, 8, 24, 9, 0) }
    author = create_user(telegram_id: 1)
    participant = create_user(telegram_id: 2)
    event = create_event(author: author, date: Date.new(2026, 8, 25), published: true)
    event.participants << participant
    bot, api = recording_bot(send_errors: [Faraday::TimeoutError.new('timeout')])
    notifier = described_class.new(bot)

    notifier.handle_3d_weather_update(event, weather(temp: 10), weather(temp: 20))

    expect(
      NotificationDelivery.where(event: event).order(:recipient_id).pluck(:chat_id, :status, :attempts)
    ).to eq([
      ['1', 'pending', 1],
      ['2', 'delivered', 1]
    ])

    notifier.handle_3d_weather_update(event, weather(temp: 10), weather(temp: 20))
    expect(api.sent_messages.map { |payload| payload[:chat_id] }).to eq(%w[1 2])

    AppClock.source = -> { Time.utc(2026, 8, 24, 9, 0, 30) }
    described_class.new(bot).process_pending_deliveries

    expect(api.sent_messages.map { |payload| payload[:chat_id] }).to eq(%w[1 2 1])
    expect(NotificationDelivery.where(event: event).pluck(:status).uniq).to eq(['delivered'])
    expect(event.reload.weather_alerts_sent).to include(
      'critical_3d' => AppClock.now.to_s
    )
  end

  it 'cancels a pending user alert after its participant leaves the event' do
    author = create_user(telegram_id: 1)
    participant = create_user(telegram_id: 2)
    event = create_event(author: author, published: true)
    event.participants << participant
    delivery = NotificationDelivery.create!(
      event: event,
      recipient: participant,
      notification_type: 'weather.critical_24h',
      context_key: described_class.context_key(event),
      idempotency_key: "weather:#{event.id}:left:user:#{participant.id}",
      chat_id: participant.telegram_id,
      payload: { text: 'Weather changed', parse_mode: 'HTML' },
      status: 'pending',
      attempts: 1,
      next_attempt_at: AppClock.now
    )
    event.participants.delete(participant)
    bot, api = recording_bot

    described_class.new(bot).process_pending_deliveries

    expect(api.sent_messages).to be_empty
    expect(delivery.reload.status).to eq('cancelled')
  end

  it 'cancels a pending user alert after its recipient is deleted' do
    author = create_user(telegram_id: 1)
    participant = create_user(telegram_id: 2)
    event = create_event(author: author, published: true)
    event.participants << participant
    delivery = NotificationDelivery.create!(
      event: event,
      recipient: participant,
      notification_type: 'weather.critical_24h',
      context_key: described_class.context_key(event),
      idempotency_key: "weather:#{event.id}:deleted:user:#{participant.id}",
      chat_id: participant.telegram_id,
      payload: { text: 'Weather changed', parse_mode: 'HTML' },
      status: 'pending',
      attempts: 1,
      next_attempt_at: AppClock.now
    )
    participant.destroy!
    bot, api = recording_bot

    described_class.new(bot).process_pending_deliveries

    expect(api.sent_messages).to be_empty
    expect(delivery.reload).to have_attributes(status: 'cancelled', recipient_id: nil)
  end

  it 'renders event details in a critical weather alert' do
    author = create_user(telegram_id: 1)
    event = create_event(author: author, published: true)
    bot, api = recording_bot

    described_class.new(bot).handle_24h_weather_update(
      event,
      weather(temp: 10),
      weather(temp: 20)
    )

    expect(api.sent_messages.first[:text]).to include(
      'Критическое изменение прогноза',
      'Для мероприятия <b>🚴‍♀️ Велосипед</b>',
      event.formatted_date
    )
    expect(api.sent_messages.first[:text]).not_to include('{{event_type}}', '{{date}}', '{{time}}')
  end

  it 'does not send the same successful critical alert twice' do
    author = create_user(telegram_id: 1)
    event = create_event(author: author, published: true)
    bot, api = recording_bot
    notifier = described_class.new(bot)

    2.times do
      notifier.handle_24h_weather_update(
        event,
        weather(temp: 10),
        weather(temp: 20)
      )
    end

    expect(api.sent_messages.map { |payload| payload[:chat_id] }).to eq([author.telegram_id])
  end

  it 'creates a new stage delivery after the event start time changes' do
    author = create_user(telegram_id: 1)
    event = create_event(author: author, published: true)
    bot, api = recording_bot
    notifier = described_class.new(bot)

    notifier.handle_24h_weather_update(event, weather(temp: 10), weather(temp: 20))
    event.update!(date: event.date + 1.day)
    notifier.handle_24h_weather_update(event, weather(temp: 10), weather(temp: 20))

    expect(api.sent_messages.map { |payload| payload[:chat_id] }).to eq(%w[1 1])
    expect(
      NotificationDelivery.where(event: event, notification_type: 'weather.critical_24h')
                          .distinct
                          .count(:context_key)
    ).to eq(2)
  end

  it 'creates a fresh stage delivery after the event moves away and back' do
    author = create_user(telegram_id: 1)
    event = create_event(author: author, published: true)
    original_date = event.date
    bot, api = recording_bot
    notifier = described_class.new(bot)

    notifier.handle_24h_weather_update(event, weather(temp: 10), weather(temp: 20))
    event.update!(date: original_date + 1.day)
    notifier.handle_24h_weather_update(event, weather(temp: 10), weather(temp: 20))
    event.update!(date: original_date)
    notifier.handle_24h_weather_update(event, weather(temp: 10), weather(temp: 20))

    expect(api.sent_messages.map { |payload| payload[:chat_id] }).to eq(%w[1 1 1])
    expect(
      NotificationDelivery.where(event: event, notification_type: 'weather.critical_24h')
                          .distinct
                          .count(:context_key)
    ).to eq(3)
  end

  it 'does not let a legacy marker suppress a stage after rescheduling' do
    author = create_user(telegram_id: 1)
    event = create_event(
      author: author,
      published: true,
      weather_alerts_sent: { 'critical_24h' => (AppClock.now - 1.day).to_s }
    )
    bot, api = recording_bot

    event.update!(date: event.date + 1.day)
    described_class.new(bot).handle_24h_weather_update(
      event,
      weather(temp: 10),
      weather(temp: 20)
    )

    expect(api.sent_messages.map { |payload| payload[:chat_id] }).to eq([author.telegram_id])
  end

  it 'cancels a pending payload after rescheduling and sends only the new event version' do
    author = create_user(telegram_id: 1)
    event = create_event(author: author, published: true)
    bot, api = recording_bot(send_errors: [Faraday::TimeoutError.new('timeout')])
    notifier = described_class.new(bot)

    notifier.handle_24h_weather_update(event, weather(temp: 10), weather(temp: 20))
    event.update!(date: event.date + 1.day)
    AppClock.source = -> { Time.utc(2026, 8, 22, 9, 0, 30) }
    notifier.process_pending_deliveries
    notifier.handle_24h_weather_update(event, weather(temp: 10), weather(temp: 20))

    expect(api.sent_messages.map { |payload| payload[:chat_id] }).to eq(%w[1 1])
    expect(
      NotificationDelivery.where(event: event).order(:id).pluck(:status)
    ).to eq(%w[cancelled delivered])
    expect(api.sent_messages.last[:text]).to include(event.formatted_date)
  end

  it 'creates a new delivery after an unpublished event is published again' do
    author = create_user(telegram_id: 1)
    event = create_event(author: author, published: true)
    bot, api = recording_bot(send_errors: [Faraday::TimeoutError.new('timeout')])
    notifier = described_class.new(bot)

    notifier.handle_24h_weather_update(event, weather(temp: 10), weather(temp: 20))
    event.update!(published: false)
    AppClock.source = -> { Time.utc(2026, 8, 22, 9, 0, 30) }
    notifier.process_pending_deliveries
    event.update!(published: true)
    notifier.handle_24h_weather_update(event, weather(temp: 10), weather(temp: 20))

    expect(api.sent_messages.map { |payload| payload[:chat_id] }).to eq(%w[1 1])
    expect(NotificationDelivery.where(event: event).order(:id).pluck(:status)).to eq(
      %w[cancelled delivered]
    )
    expect(NotificationDelivery.where(event: event).distinct.count(:context_key)).to eq(2)
  end

  it 'delivers at most one critical alert for each of the 3d and 24h stages' do
    AppClock.source = -> { Time.zone.local(2026, 8, 24, 12, 0) }
    author = create_user(telegram_id: 1)
    event = create_event(author: author, date: Date.new(2026, 8, 25), published: true)
    bot, api = recording_bot
    notifier = described_class.new(bot)

    2.times do
      notifier.handle_3d_weather_update(event, weather(temp: 10), weather(temp: 20))
    end
    2.times do
      notifier.handle_24h_weather_update(event, weather(temp: 20), weather(temp: 5))
    end

    expect(api.sent_messages.map { |payload| payload[:chat_id] }).to eq(
      [author.telegram_id, author.telegram_id]
    )
    expect(event.reload.weather_alerts_sent).to include(
      'critical_3d' => AppClock.now.to_s,
      'critical_24h' => AppClock.now.to_s
    )
  end

  it 'does not let the ambiguous legacy marker suppress a new 24h stage' do
    author = create_user(telegram_id: 1)
    event = create_event(
      author: author,
      published: true,
      weather_alerts_sent: { '24h_critical' => (AppClock.now - 2.days).to_s }
    )
    bot, api = recording_bot

    described_class.new(bot).handle_24h_weather_update(event, weather(temp: 10), weather(temp: 20))

    expect(api.sent_messages.map { |payload| payload[:chat_id] }).to eq([author.telegram_id])
    expect(event.reload.weather_alerts_sent).to include(
      '24h_critical',
      'critical_24h' => AppClock.now.to_s
    )
  end

  it 'persists a successful critical delivery independently of invalid unsaved event changes' do
    author = create_user(telegram_id: 1)
    event = create_event(author: author, published: true)
    event.location = nil
    bot, = recording_bot

    described_class.new(bot).handle_24h_weather_update(event, weather(temp: 10), weather(temp: 20))

    expect(NotificationDelivery.last.status).to eq('delivered')
    expect(event.reload.weather_alerts_sent).to have_key('critical_24h')
  end

  it 'does not mark an accurate forecast as sent when every user delivery fails' do
    author = create_user(telegram_id: 1)
    event = create_event(author: author, published: true)
    bot, api = recording_bot(send_errors: [Faraday::TimeoutError.new('timeout')])
    fallback_weather = weather(temp: 10).merge('is_fallback' => true, 'fallback_from' => '2026-08-25')

    described_class.new(bot).handle_3d_weather_update(event, fallback_weather, weather(temp: 12))

    expect(api.sent_messages.map { |payload| payload[:chat_id] }).to eq([author.telegram_id])
    expect(event.reload.weather_alerts_sent).not_to have_key('3d_accurate')
  end

  it 'delivers an accurate forecast to users and refreshes the published channel message' do
    AppClock.source = -> { Time.zone.local(2026, 8, 24, 12, 0) }
    author = create_user(telegram_id: 1)
    participant = create_user(telegram_id: 2)
    event = create_event(
      author: author,
      date: Date.new(2026, 8, 25),
      published: true,
      channel_message_id: 42,
      weather_data: weather(temp: 12)
    )
    event.participants << participant
    bot, api = recording_bot
    fallback_weather = weather(temp: 10).merge(
      'is_fallback' => true,
      'fallback_from' => '2026-08-25'
    )

    described_class.new(bot).handle_3d_weather_update(
      event,
      fallback_weather,
      weather(temp: 12)
    )

    expect(api.sent_messages.map { |payload| payload[:chat_id] }).to contain_exactly('1', '2')
    expect(api.sent_messages.first[:text]).to include(
      'Для мероприятия <b>🚴‍♀️ Велосипед</b>',
      event.formatted_date,
      'приблизительный прогноз',
      'Сейчас: точный прогноз - Ясно, 12°C'
    )
    expect(api.sent_messages.first[:text]).not_to include('{{event_type}}', '{{date}}', '{{time}}')
    expect(api.edited_messages.last).to include(
      chat_id: '@veloutro',
      message_id: 42,
      parse_mode: 'HTML'
    )
    expect(event.reload.weather_alerts_sent).to include(
      '3d_accurate' => AppClock.now.to_s
    )
  end

  it 'does not send the same successful accurate forecast twice' do
    author = create_user(telegram_id: 1)
    event = create_event(
      author: author,
      date: Date.new(2026, 8, 25),
      published: true,
      channel_message_id: 42,
      weather_data: weather(temp: 12)
    )
    bot, api = recording_bot
    notifier = described_class.new(bot)
    fallback_weather = weather(temp: 10).merge(
      'is_fallback' => true,
      'fallback_from' => '2026-08-25'
    )

    2.times do
      notifier.handle_3d_weather_update(event, fallback_weather, weather(temp: 12))
    end

    expect(api.sent_messages.map { |payload| payload[:chat_id] }).to eq([author.telegram_id])
    expect(api.edited_messages.length).to eq(1)
  end

  it 'retries a failed channel message refresh through the outbox' do
    author = create_user(telegram_id: 1)
    event = create_event(
      author: author,
      published: true,
      channel_message_id: 42,
      weather_data: weather(temp: 11)
    )
    bot, api = recording_bot(edit_errors: [Faraday::TimeoutError.new('timeout')])
    notifier = described_class.new(bot)

    notifier.handle_24h_weather_update(event, weather(temp: 10), weather(temp: 11))
    expect(NotificationDelivery.last).to have_attributes(
      operation: 'edit_message_text',
      status: 'pending',
      attempts: 1
    )

    AppClock.source = -> { Time.utc(2026, 8, 22, 9, 0, 30) }
    notifier.process_pending_deliveries

    expect(api.edited_messages.length).to eq(2)
    expect(NotificationDelivery.last.reload.status).to eq('delivered')
  end

  it 'cancels a failed channel refresh after its rendered event payload changes' do
    author = create_user(telegram_id: 1)
    participant = create_user(telegram_id: 2)
    event = create_event(
      author: author,
      published: true,
      channel_message_id: 42,
      weather_data: weather(temp: 11)
    )
    bot, api = recording_bot(edit_errors: [Faraday::TimeoutError.new('timeout')])
    notifier = described_class.new(bot)

    notifier.handle_24h_weather_update(event, weather(temp: 10), weather(temp: 11))
    event.update!(location: 'Новое место')
    event.participants << participant
    AppClock.source = -> { Time.utc(2026, 8, 22, 9, 0, 30) }

    notifier.process_pending_deliveries

    expect(api.edited_messages.length).to eq(1)
    expect(NotificationDelivery.last.reload.status).to eq('cancelled')
  end

  it 'reconciles a missing event marker without resending a delivered message' do
    author = create_user(telegram_id: 1)
    event = create_event(author: author, published: true)
    NotificationDelivery.create!(
      event: event,
      recipient: author,
      notification_type: 'weather.critical_24h',
      context_key: described_class.context_key(event),
      idempotency_key: "weather:#{event.id}:reconciliation-gap:user:#{author.id}",
      chat_id: author.telegram_id,
      payload: { text: 'Delivered weather alert', parse_mode: 'HTML' },
      status: 'delivered',
      attempts: 1,
      delivered_at: AppClock.now
    )
    bot, api = recording_bot

    described_class.new(bot).process_pending_deliveries

    expect(api.sent_messages).to be_empty
    expect(event.reload.weather_alerts_sent).to have_key('critical_24h')
    expect(NotificationDelivery.last.reload.finalized_at).to eq(AppClock.now)
  end

  it 'reconciles every missing marker when more than one batch was delivered' do
    author = create_user(telegram_id: 1)
    events = 101.times.map do |index|
      event = create_event(author: author, published: true)
      NotificationDelivery.create!(
        event: event,
        recipient: author,
        notification_type: 'weather.critical_24h',
        context_key: described_class.context_key(event),
        idempotency_key: "weather:#{event.id}:reconciliation:#{index}",
        chat_id: author.telegram_id,
        payload: { text: 'Delivered weather alert', parse_mode: 'HTML' },
        status: 'delivered',
        attempts: 1,
        delivered_at: AppClock.now
      )
      event
    end
    bot, api = recording_bot

    described_class.new(bot).process_pending_deliveries

    expect(api.sent_messages).to be_empty
    expect(events.count { |event| event.reload.weather_alerts_sent.key?('critical_24h') }).to eq(101)
    expect(NotificationDelivery.where(finalized_at: nil)).to be_empty
  end

  it 'retires delivered rows from reconciliation after a stage partially fails' do
    author = create_user(telegram_id: 1)
    participant = create_user(telegram_id: 2)
    event = create_event(author: author, published: true)
    context_key = described_class.context_key(event)
    delivered = NotificationDelivery.create!(
      event: event,
      recipient: author,
      notification_type: 'weather.critical_24h',
      context_key: context_key,
      idempotency_key: "weather:#{event.id}:partial-terminal:user:#{author.id}",
      chat_id: author.telegram_id,
      payload: { text: 'Delivered weather alert' },
      status: 'delivered',
      attempts: 1,
      delivered_at: AppClock.now
    )
    failed = NotificationDelivery.create!(
      event: event,
      recipient: participant,
      notification_type: 'weather.critical_24h',
      context_key: context_key,
      idempotency_key: "weather:#{event.id}:partial-terminal:user:#{participant.id}",
      chat_id: participant.telegram_id,
      payload: { text: 'Failed weather alert' },
      status: 'failed',
      attempts: NotificationDelivery::MAX_ATTEMPTS,
      last_error: 'Faraday::TimeoutError: timeout'
    )
    bot, api = recording_bot

    described_class.new(bot).process_pending_deliveries

    expect(api.sent_messages).to be_empty
    expect(event.reload.weather_alerts_sent).not_to have_key('critical_24h')
    expect(delivered.reload.finalized_at).to eq(AppClock.now)
    expect(failed.reload.finalized_at).to be_nil
  end

  def weather(temp:)
    {
      'temp_c' => temp,
      'feelslike_c' => temp,
      'condition' => 'Ясно',
      'wind_kph' => 5,
      'precip_prob' => 10,
      'alerts' => []
    }
  end
end

RSpec.describe Bot::Helpers::WeatherAdminNotifier do
  it 'continues with the remaining administrators after one delivery fails' do
    use_app_config('ADMIN_IDS' => %w[101 202])
    bot, api = recording_bot(send_errors: [Faraday::TimeoutError.new('timeout')])

    described_class.new(bot).send_alert(:error, 'WeatherAPI unavailable', status: 503)

    expect(api.sent_messages.map { |payload| payload[:chat_id] }).to eq(%w[101 202])
    expect(api.sent_messages.last[:text]).to include('WeatherAPI unavailable', 'HTTP Status: 503')
  end
end
