require 'integration_helper'

RSpec.describe Bot::Helpers::Formatter do
  describe '.event_info' do
    it 'escapes user-provided HTML and displays participants' do
      author = create_user(telegram_id: 1, username: '<b>Организатор</b>')
      participant = create_user(telegram_id: 2, nickname: 'rider')
      event = create_event(
        author: author,
        location: '<script>&',
        additional_info: 'Берём <фонари>',
        map: 'https://example.test/route?a=1&b=2'
      )
      event.participants << participant

      text = described_class.event_info(event)

      expect(text).to include(
        '&lt;script&gt;&amp;',
        'Берём &lt;фонари&gt;',
        '&lt;b&gt;Организатор&lt;/b&gt;',
        'https://example.test/route?a=1&amp;b=2',
        '@rider'
      )
      expect(text).not_to include('<script>', '<b>Организатор</b>')
    end

    it 'omits optional active-event fields when they are absent' do
      author = create_user(telegram_id: 1)
      event = create_event(
        author: author,
        event_type: '🎲 Настолки',
        distance: nil,
        pace: nil,
        track: nil,
        map: nil,
        additional_info: nil
      )

      text = described_class.event_info(event)

      expect(text).not_to include('📏 Расстояние:', '🚴‍♀️ Темп/Скорость:', '🛤️ Трек:', '🗺️ Карта:', '📝 Описание:')
    end
  end
end
