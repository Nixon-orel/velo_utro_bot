require 'integration_helper'

RSpec.describe User do
  it 'uses Telegram nickname, first name, and a stable fallback in display priority order' do
    with_nickname = create_user(telegram_id: 101, username: 'Никита', nickname: 'nixon')
    with_first_name = create_user(telegram_id: 202, username: 'Мария', nickname: nil)
    anonymous = create_user(telegram_id: 123_456, username: 'Пользователь', nickname: nil)

    expect(with_nickname.display_name).to eq('@nixon')
    expect(with_first_name.display_name).to eq('Мария')
    expect(anonymous.display_name).to eq('Пользователь 3456')
  end

  it 'creates an anonymous Telegram user with a readable fallback name' do
    telegram_user_record = OpenStruct.new(id: 987_654, first_name: nil, username: nil)

    user = described_class.find_or_create_from_telegram(telegram_user_record)

    expect(user).to have_attributes(username: 'Пользователь', nickname: nil)
    expect(user.display_name).to eq('Пользователь 7654')
  end

  it 'checks administrator access against normalized Telegram identifiers' do
    use_app_config('ADMIN_IDS' => %w[101 303])

    expect(create_user(telegram_id: 101)).to be_admin
    expect(create_user(telegram_id: 202)).not_to be_admin
  end

  it 'updates Telegram profile fields without creating another user' do
    user = create_user(telegram_id: 101, username: 'Старое имя', nickname: 'old')
    telegram_user_record = OpenStruct.new(id: 101, first_name: 'Новое имя', username: 'new')

    result = described_class.find_or_create_from_telegram(telegram_user_record)

    expect(result.id).to eq(user.id)
    expect(result).to have_attributes(username: 'Новое имя', nickname: 'new')
    expect(described_class.where(telegram_id: '101').count).to eq(1)
  end

  it 'creates one user when first updates arrive concurrently', :concurrent do
    telegram_user_record = OpenStruct.new(id: 101, first_name: 'Никита', username: 'nixon')
    ready = Queue.new
    gate = Queue.new
    users = Queue.new
    errors = Queue.new
    creation_barrier = lambda do
      ready << true
      gate.pop
    end
    described_class.set_callback(:create, :before, creation_barrier)

    begin
      threads = 4.times.map do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            users << described_class.find_or_create_from_telegram(telegram_user_record)
          end
        rescue => e
          errors << e
        end
      end
      threads.count.times { queue_pop(ready) }
    ensure
      threads&.count.to_i.times { gate << true }
      begin
        join_threads(threads) if threads
      ensure
        described_class.skip_callback(:create, :before, creation_barrier)
      end
    end

    captured_errors = errors.size.times.map { queue_pop(errors) }
    expect(captured_errors).to be_empty,
                               captured_errors.map { |error| "#{error.class}: #{error.message}" }.join("\n")
    expect(described_class.where(telegram_id: '101').count).to eq(1)
    expect(threads.count.times.map { queue_pop(users).id }.uniq.one?).to be(true)
  end
end
