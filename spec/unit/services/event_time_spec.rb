require 'spec_helper'

RSpec.describe EventTime do
  describe '.valid_input?' do
    it 'accepts an exact 24-hour time' do
      expect(described_class.valid_input?('00:00')).to be(true)
      expect(described_class.valid_input?('23:59')).to be(true)
    end

    it 'rejects legacy and out-of-range values for new input' do
      expect(described_class.valid_input?('9:05')).to be(false)
      expect(described_class.valid_input?('09:05 - 10:30')).to be(false)
      expect(described_class.valid_input?('24:00')).to be(false)
      expect(described_class.valid_input?('12:60')).to be(false)
    end
  end

  describe '.parse' do
    it 'builds the start time in the requested timezone' do
      parsed = described_class.parse(date: Date.new(2026, 8, 22), time: '09:05', timezone: 'UTC')

      expect(parsed).to eq(ActiveSupport::TimeZone['UTC'].local(2026, 8, 22, 9, 5))
    end

    it 'reads a legacy time range with surrounding whitespace' do
      parsed = described_class.parse(date: '2026-08-22', time: ' 9:05 - 10:30 ')

      expect(parsed).to eq(ActiveSupport::TimeZone['Europe/Moscow'].local(2026, 8, 22, 9, 5))
    end

    it 'returns nil for an invalid date or time' do
      expect(described_class.parse(date: 'not-a-date', time: '09:05')).to be_nil
      expect(described_class.parse(date: '2026-08-22', time: '25:00')).to be_nil
    end
  end
end
