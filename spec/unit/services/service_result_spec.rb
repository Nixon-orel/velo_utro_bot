require 'spec_helper'

RSpec.describe ServiceResult do
  describe '.success' do
    it 'stores a value and immutable metadata' do
      result = described_class.success(:event, delivered: 2)

      expect(result).to be_success
      expect(result).not_to be_failure
      expect(result.value).to eq(:event)
      expect(result.metadata).to eq(delivered: 2)
      expect(result.metadata).to be_frozen
    end
  end

  describe '.failure' do
    it 'stores the error code, error, and value' do
      error = StandardError.new('failed')
      result = described_class.failure(:delivery_failed, error: error, value: :event)

      expect(result).to be_failure
      expect(result.error_code).to eq(:delivery_failed)
      expect(result.error).to equal(error)
      expect(result.value).to eq(:event)
    end
  end
end
