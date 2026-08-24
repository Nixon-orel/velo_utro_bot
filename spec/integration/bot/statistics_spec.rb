require 'integration_helper'

RSpec.describe Bot::Helpers::Statistics do
  subject(:statistics) { described_class.new }

  describe '#monthly_report' do
    it 'aggregates only the selected month and handles distance formats' do
      organizer = create_user(telegram_id: 1, nickname: 'organizer')
      other_author = create_user(telegram_id: 2, username: 'Другой автор')
      active_participant = create_user(telegram_id: 3, nickname: 'active')

      first = create_event(
        author: organizer,
        date: Date.new(2026, 7, 5),
        event_type: '🚴‍♀️ Велосипед',
        distance: 'около 20 км'
      )
      second = create_event(
        author: organizer,
        date: Date.new(2026, 7, 12),
        event_type: '🚴‍♀️ Велосипед',
        distance: '15km'
      )
      third = create_event(
        author: other_author,
        date: Date.new(2026, 7, 20),
        event_type: '🎲 Настолки',
        distance: nil
      )
      create_event(
        author: other_author,
        date: Date.new(2026, 8, 1),
        event_type: '🚴‍♀️ Велосипед',
        distance: '100 км'
      )
      [first, second, third].each { |event| event.participants << active_participant }

      report = statistics.monthly_report(7, 2026)

      expect(report).to include(
        total_events: 3,
        bike_events: 2,
        total_kilometers: 35,
        other_events: { '🎲 Настолки' => 1 },
        top_organizer: { display_name: '@organizer', count: 2 },
        most_active_participant: { display_name: '@active', count: 3 }
      )
      expect(report[:period]).to eq('Июль 2026')
    end

    it 'selects December when the current month is January' do
      AppClock.source = -> { Time.utc(2026, 1, 15, 12, 0) }
      author = create_user(telegram_id: 1)
      create_event(author: author, date: Date.new(2025, 12, 20))
      create_event(author: author, date: Date.new(2026, 1, 2))

      report = statistics.monthly_report

      expect(report).to include(period: 'Декабрь 2025', total_events: 1)
    end
  end

  describe '#format_monthly_report' do
    it 'formats counts and optional leaders for Telegram HTML' do
      text = statistics.format_monthly_report(
        period: 'Июль 2026',
        total_events: 3,
        bike_events: 2,
        total_kilometers: 35,
        other_events: { '🎲 Настолки' => 1 },
        top_organizer: { display_name: '@organizer', count: 2 },
        most_active_participant: { display_name: '@active', count: 3 }
      )

      expect(text).to include(
        'Статистика велобота за Июль 2026',
        'Прокатано километров: <b>35 км</b>',
        '🎲 Настолки: 1',
        '@organizer (создано 2 события)',
        '@active (участвовал(а) в 3 события)'
      )
    end
  end
end
