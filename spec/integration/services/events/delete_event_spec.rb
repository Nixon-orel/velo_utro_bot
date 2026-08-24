require 'integration_helper'

RSpec.describe Events::DeleteEvent do
  it 'deletes an authored event and returns its participants for later notification' do
    author = create_user(telegram_id: 1)
    participant = create_user(telegram_id: 2)
    event = create_event(author: author)
    event.participants << participant

    result = nil
    expect do
      result = described_class.call(event: event, actor: author)
    end.to change(Event, :count).by(-1)

    expect(result).to be_success
    expect(result.value).to be_destroyed
    expect(result.metadata[:participants]).to eq([participant])
  end

  it 'keeps the event when the actor is not its author' do
    author = create_user(telegram_id: 1)
    stranger = create_user(telegram_id: 2)
    event = create_event(author: author)

    expect do
      result = described_class.call(event: event, actor: stranger)
      expect(result.error_code).to eq(:forbidden)
    end.not_to change(Event, :count)
  end
end
