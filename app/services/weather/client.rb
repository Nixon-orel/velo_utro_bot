require 'faraday'
require 'json'

module Weather
  class Client
    API_BASE_URL = 'https://api.weatherapi.com/v1'
    RETRYABLE_STATUSES = [429, 500, 502, 503, 504].freeze
    MAX_RETRIES = 2

    def initialize(api_key:, reporter:, connection: nil, sleeper: nil)
      @api_key = api_key
      @reporter = reporter
      @connection = connection || build_connection
      @sleeper = sleeper || ->(seconds) { sleep(seconds) }
    end

    def fetch_forecast(coordinates)
      return report_missing_api_key(coordinates) if @api_key.to_s.empty?

      retry_count = 0
      loop do
        response = request(coordinates)
        return parse(response, coordinates) if response.success?

        data = response_error_data(response, coordinates, retry_count)
        unless retryable?(response.status, retry_count)
          report(:error, "Weather API returned status #{response.status}", data)
          return nil
        end

        report(:warn, 'Retrying weather API request', data)
        wait_before_retry(retry_count)
        retry_count += 1
      rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
        data = { coordinates: coordinates, retry_count: retry_count, error: e.class.name }
        unless retry_count < MAX_RETRIES
          report(:error, 'Weather API request failed after retries', data)
          return nil
        end

        report(:warn, 'Retrying weather API request after network failure', data)
        wait_before_retry(retry_count)
        retry_count += 1
      rescue JSON::ParserError => e
        report(:error, 'Invalid JSON response from weather API', coordinates: coordinates, error: e.message)
        return nil
      rescue => e
        report(
          :error,
          'Unexpected weather API error',
          coordinates: coordinates,
          retry_count: retry_count,
          error: e.class.name,
          message: e.message
        )
        return nil
      end
    end

    private

    def request(coordinates)
      @connection.get('forecast.json', {
        key: @api_key,
        q: coordinates.to_s.gsub(/\s+/, ''),
        days: 14,
        aqi: 'no',
        lang: 'ru'
      })
    end

    def parse(response, coordinates)
      JSON.parse(response.body).tap do
        report(:debug, 'Weather data fetched', coordinates: coordinates)
      end
    end

    def response_error_data(response, coordinates, retry_count)
      {
        coordinates: coordinates,
        status: response.status,
        body: response.body.to_s[0..500],
        retry_count: retry_count
      }
    end

    def retryable?(status, retry_count)
      retry_count < MAX_RETRIES && RETRYABLE_STATUSES.include?(status)
    end

    def wait_before_retry(retry_count)
      @sleeper.call(2**retry_count)
    end

    def report_missing_api_key(coordinates)
      report(:error, 'Weather API key not configured', coordinates: coordinates)
      nil
    end

    def report(level, message, data)
      @reporter.call(level, message, data)
    end

    def build_connection
      Faraday.new(url: API_BASE_URL) do |faraday|
        faraday.request :url_encoded
        faraday.adapter Faraday.default_adapter
        faraday.options.timeout = 10
      end
    end
  end
end
