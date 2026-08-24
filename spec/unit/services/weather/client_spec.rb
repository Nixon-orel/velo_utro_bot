require 'spec_helper'

RSpec.describe Weather::Client do
  subject(:client) do
    described_class.new(
      api_key: api_key,
      reporter: reporter,
      sleeper: ->(seconds) { sleep_delays << seconds }
    )
  end

  let(:api_key) { 'test-weather-key' }
  let(:reports) { [] }
  let(:reporter) { ->(level, message, data) { reports << [level, message, data] } }
  let(:sleep_delays) { [] }
  let(:endpoint) { 'https://api.weatherapi.com/v1/forecast.json' }
  let(:query) do
    {
      key: api_key,
      q: '52.1,36.2',
      days: 14,
      aqi: 'no',
      lang: 'ru'
    }
  end

  describe '#fetch_forecast' do
    it 'returns parsed JSON from WeatherAPI over HTTPS' do
      request = stub_request(:get, endpoint)
                .with(query: query)
                .to_return(status: 200, body: '{"location":{"name":"Orel"}}')

      expect(client.fetch_forecast('52.1, 36.2')).to eq('location' => { 'name' => 'Orel' })
      expect(request).to have_been_requested.once
    end

    it 'does not make a request without an API key' do
      empty_key_client = described_class.new(api_key: nil, reporter: reporter)

      expect(empty_key_client.fetch_forecast('52.1,36.2')).to be_nil
      expect(a_request(:any, /weatherapi/)).not_to have_been_made
      expect(reports.last.first(2)).to eq([:error, 'Weather API key not configured'])
    end

    it 'retries a transient server failure and returns the next successful response' do
      request = stub_request(:get, endpoint)
                .with(query: query)
                .to_return(
                  { status: 500, body: '{"error":"temporary"}' },
                  { status: 200, body: '{"forecast":{"forecastday":[]}}' }
                )

      expect(client.fetch_forecast('52.1,36.2')).to eq('forecast' => { 'forecastday' => [] })
      expect(request).to have_been_requested.twice
      expect(sleep_delays).to eq([1])
    end

    it 'stops after the configured number of rate-limit retries' do
      request = stub_request(:get, endpoint)
                .with(query: query)
                .to_return(status: 429, body: '{"error":"rate limit"}')

      expect(client.fetch_forecast('52.1,36.2')).to be_nil
      expect(request).to have_been_requested.times(3)
      expect(sleep_delays).to eq([1, 2])
      expect(reports.last.first(2)).to eq([:error, 'Weather API returned status 429'])
      expect(reports.last.last).to include(
        status: 429,
        retry_count: 2,
        coordinates: '52.1,36.2'
      )
    end

    it 'returns nil for invalid JSON without retrying' do
      request = stub_request(:get, endpoint)
                .with(query: query)
                .to_return(status: 200, body: 'not-json')

      expect(client.fetch_forecast('52.1,36.2')).to be_nil
      expect(request).to have_been_requested.once
      expect(sleep_delays).to be_empty
      expect(reports.last.first(2)).to eq([:error, 'Invalid JSON response from weather API'])
    end

    it 'stops after the configured number of network retries' do
      request = stub_request(:get, endpoint)
                .with(query: query)
                .to_timeout

      expect(client.fetch_forecast('52.1,36.2')).to be_nil
      expect(request).to have_been_requested.times(3)
      expect(sleep_delays).to eq([1, 2])
      expect(reports.last.first(2)).to eq([:error, 'Weather API request failed after retries'])
    end

    it 'does not retry a non-transient client error' do
      request = stub_request(:get, endpoint)
                .with(query: query)
                .to_return(status: 400, body: '{"error":"bad request"}')

      expect(client.fetch_forecast('52.1,36.2')).to be_nil
      expect(request).to have_been_requested.once
      expect(sleep_delays).to be_empty
      expect(reports.last.first(2)).to eq([:error, 'Weather API returned status 400'])
    end
  end
end
