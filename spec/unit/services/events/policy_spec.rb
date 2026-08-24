require 'spec_helper'

RSpec.describe Events::Policy do
  EventRecord = Struct.new(:author_id)
  Actor = Struct.new(:id)

  describe '.manage?' do
    it 'allows the event author' do
      expect(described_class.manage?(event: EventRecord.new(10), actor: Actor.new(10))).to be(true)
    end

    it 'rejects another user and missing records' do
      expect(described_class.manage?(event: EventRecord.new(10), actor: Actor.new(11))).to be(false)
      expect(described_class.manage?(event: nil, actor: Actor.new(10))).to be_nil
      expect(described_class.manage?(event: EventRecord.new(10), actor: nil)).to be_nil
    end
  end
end
