require 'spec_helper'

RSpec.describe 'application environment' do
  it 'preserves the receiver timezone when ActiveSupport converts to Time' do
    expect(ActiveSupport.to_time_preserves_timezone).to eq(:zone)
  end
end
