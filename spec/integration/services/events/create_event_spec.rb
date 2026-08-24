require 'integration_helper'

RSpec.describe Events::CreateEvent do
  let(:author) { create_user(telegram_id: 1) }
  let(:attributes) do
    {
      author_id: author.id,
      date: Date.new(2026, 8, 23),
      time: '09:00',
      event_type: '🚴‍♀️ Велосипед',
      location: 'Орёл'
    }
  end

  describe '.call' do
    it 'persists one valid event' do
      result = nil

      expect do
        result = described_class.call(attributes: attributes)
      end.to change(Event, :count).by(1)

      expect(result).to be_success
      expect(result.value).to be_persisted
      expect(result.value).to have_attributes(attributes)
    end

    it 'returns a validation failure without persisting an invalid event' do
      result = nil

      expect do
        result = described_class.call(attributes: attributes.merge(location: nil))
      end.not_to change(Event, :count)

      expect(result).to be_failure
      expect(result.error_code).to eq(:validation_failed)
      expect(result.value.errors[:location]).not_to be_empty
    end
  end

  describe '.from_session' do
    it 'maps session values and extra attributes into one event' do
      session = Struct.new(:new_event).new(
        {
          'author_id' => author.id,
          'date' => '2026-08-24',
          'time' => '10:30',
          'type' => '🚴‍♀️ Велосипед',
          'location' => 'Парк',
          'distance' => '25 км'
        }
      )

      result = nil
      expect do
        result = described_class.from_session(
          session: session,
          extra_attributes: { weather_city: 'Орёл' }
        )
      end.to change(Event, :count).by(1)

      expect(result).to be_success
      expect(result.value).to have_attributes(
        date: Date.new(2026, 8, 24),
        time: '10:30',
        distance: '25 км',
        weather_city: 'Орёл'
      )
    end

    it 'rejects an invalid session date before persistence' do
      session = Struct.new(:new_event).new(attributes.stringify_keys.merge('date' => 'bad-date'))

      expect do
        result = described_class.from_session(session: session)
        expect(result.error_code).to eq(:invalid_date)
      end.not_to change(Event, :count)
    end

    it 'consumes a persisted creation state together with the event' do
      session = persisted_creation_session
      first = nil
      second = nil

      expect do
        first = described_class.from_session(
          session: session,
          expected_state: 'enter_additional_info'
        )
        second = described_class.from_session(
          session: session,
          expected_state: 'enter_additional_info'
        )
      end.to change(Event, :count).by(1)

      expect(first).to be_success
      expect(second).to be_failure
      expect(second.error_code).to eq(:already_processed)
      expect(session.reload.state).to be_nil
    end

    it 'rolls back the event when completing the session fails' do
      session = persisted_creation_session
      allow_any_instance_of(Session).to receive(:save!).and_raise(
        ActiveRecord::StatementInvalid.new('session write failed')
      )

      expect do
        result = described_class.from_session(
          session: session,
          expected_state: 'enter_additional_info'
        )
        expect(result).to be_failure
        expect(result.error_code).to eq(:persistence_failed)
      end.not_to change(Event, :count)

      expect(session.reload.state).to eq('enter_additional_info')
    end

    it 'does not turn a committed creation into a failure because of a later reload' do
      session = persisted_creation_session
      allow(session).to receive(:reload).and_raise(
        ActiveRecord::StatementInvalid.new('read after commit failed')
      )
      result = nil

      expect do
        result = described_class.from_session(
          session: session,
          expected_state: 'enter_additional_info'
        )
      end.to change(Event, :count).by(1)

      expect(result).to be_success
      expect(Session.find(session.id).state).to be_nil
    end

    it 'does not keep the session row locked while preparing external attributes', :concurrent do
      session = persisted_creation_session
      provider_entered = Queue.new
      release_provider = Queue.new
      results = Queue.new
      errors = Queue.new

      worker = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          results << described_class.from_session(
            session: Session.find(session.id),
            expected_state: 'enter_additional_info'
          ) do
            provider_entered << true
            queue_pop(release_provider)
            {}
          end
        end
      rescue => e
        errors << e
      end

      lock_error = nil
      begin
        queue_pop(provider_entered)
        ActiveRecord::Base.connection_pool.with_connection do
          Session.transaction do
            Session.lock('FOR UPDATE NOWAIT').find(session.id)
          end
        end
      rescue ActiveRecord::StatementInvalid => e
        lock_error = e
      ensure
        release_provider << true
        join_threads([worker])
      end

      raise errors.pop unless errors.empty?

      expect(lock_error).to be_nil
      expect(queue_pop(results)).to be_success
      expect(Event.count).to eq(1)
    end

    it 'keeps a replacement claim when ownership changes during preparation' do
      session = persisted_creation_session
      replacement_claim = {
        'token' => 'replacement-worker',
        'claimed_at' => AppClock.now.to_f
      }

      result = described_class.from_session(
        session: session,
        expected_state: 'enter_additional_info'
      ) do
        replacement_session = Session.find(session.id)
        replacement_session[described_class::CREATION_CLAIM_KEY] = replacement_claim
        replacement_session.save!
        {}
      end

      expect(result).to be_failure
      expect(result.error_code).to eq(:claim_lost)
      expect(Event.count).to eq(0)
      expect(session.reload[described_class::CREATION_CLAIM_KEY]).to eq(replacement_claim)
    end

    it 'releases its claim when external attribute preparation raises' do
      session = persisted_creation_session

      expect do
        described_class.from_session(
          session: session,
          expected_state: 'enter_additional_info'
        ) do
          raise 'weather preparation failed'
        end
      end.to raise_error(RuntimeError, 'weather preparation failed')

      session.reload
      expect(session.state).to eq('enter_additional_info')
      expect(session[described_class::CREATION_CLAIM_KEY]).to be_nil
      expect(Event.count).to eq(0)
    end

    it 'returns a persistence failure when the session disappears before finalization' do
      session = persisted_creation_session

      result = described_class.from_session(
        session: session,
        expected_state: 'enter_additional_info'
      ) do
        Session.find(session.id).destroy!
        {}
      end

      expect(result).to be_failure
      expect(result.error_code).to eq(:persistence_failed)
      expect(Event.count).to eq(0)
      expect(Session.exists?(session.id)).to be(false)
    end

    it 'releases its claim after final attribute validation fails' do
      session = persisted_creation_session

      result = described_class.from_session(
        session: session,
        expected_state: 'enter_additional_info'
      ) do
        { location: nil }
      end

      expect(result).to be_failure
      expect(result.error_code).to eq(:validation_failed)
      expect(Event.count).to eq(0)
      session.reload
      expect(session.state).to eq('enter_additional_info')
      expect(session[described_class::CREATION_CLAIM_KEY]).to be_nil
    end
  end

  def persisted_creation_session
    Session.create!(
      user_id: author.telegram_id,
      data: {
        'state' => 'enter_additional_info',
        'new_event' => {
          'author_id' => author.id,
          'date' => '2026-08-24',
          'time' => '10:30',
          'type' => '🚴‍♀️ Велосипед',
          'location' => 'Парк'
        }
      }
    )
  end
end
