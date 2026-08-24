require 'integration_helper'

RSpec.describe Events::EditEvent do
  it 'returns only business fields that were changed' do
    author = create_user(telegram_id: 1)
    event = create_event(author: author, location: 'Сквер')

    result = described_class.call(
      event: event,
      actor: author,
      changes: { location: 'Парк' }
    )

    expect(result).to be_success
    expect(result.metadata[:changed_fields]).to eq([:location])
  end

  it 'rejects changes from another user' do
    author = create_user(telegram_id: 1)
    stranger = create_user(telegram_id: 2)
    event = create_event(author: author, location: 'Сквер')

    result = described_class.call(event: event, actor: stranger, changes: { location: 'Парк' })

    expect(result).to be_failure
    expect(result.error_code).to eq(:forbidden)
    expect(event.reload.location).to eq('Сквер')
  end

  it 'ignores attributes outside the editable allowlist' do
    author = create_user(telegram_id: 1)
    event = create_event(author: author, location: 'Сквер', published: false)

    result = described_class.call(
      event: event,
      actor: author,
      changes: { location: 'Парк', published: true }
    )

    expect(result).to be_success
    expect(event.reload).to have_attributes(location: 'Парк', published: false)
    expect(result.metadata[:changed_fields]).to eq([:location])
  end

  it 'does not persist an invalid new time' do
    author = create_user(telegram_id: 1)
    event = create_event(author: author, time: '09:00')

    result = described_class.call(event: event, actor: author, changes: { time: '9:00' })

    expect(result).to be_failure
    expect(result.error_code).to eq(:validation_failed)
    expect(event.reload.time).to eq('09:00')
  end
end
