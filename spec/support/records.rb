module TestRecords
  def create_user(telegram_id:, username: 'Test user', nickname: nil, **attributes)
    User.create!(
      {
        telegram_id: telegram_id.to_s,
        username: username,
        nickname: nickname
      }.merge(attributes)
    )
  end

  def create_event(author:, **attributes)
    Event.create!(
      {
        author: author,
        date: Date.new(2026, 8, 23),
        time: '09:00',
        event_type: '🚴‍♀️ Велосипед',
        location: 'Орёл'
      }.merge(attributes)
    )
  end
end

RSpec.configure do |config|
  config.include TestRecords
end
