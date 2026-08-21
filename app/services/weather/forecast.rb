module Weather
  class Forecast
    def self.for_event(data:, event_date:, event_time:)
      requested_date = normalize_date(event_date)
      event_hour = event_time.to_s.split(':').first.to_i
      days = data.dig('forecast', 'forecastday').to_a
      forecast_day = days.find { |day| day['date'] == requested_date } || days.last
      return nil unless forecast_day

      fallback = forecast_day['date'] != requested_date
      hourly = forecast_day['hour'].to_a.find do |hour|
        hour['time'].to_s.end_with?(" #{event_hour.to_s.rjust(2, '0')}:00")
      end

      values = hourly ? hourly_values(hourly) : daily_values(forecast_day['day'].to_h)
      values.merge(
        'sunrise' => forecast_day.dig('astro', 'sunrise'),
        'sunset' => forecast_day.dig('astro', 'sunset'),
        'alerts' => normalize_alerts(data['alerts']),
        'forecast_date' => requested_date,
        'forecast_time' => event_time,
        'is_fallback' => fallback,
        'fallback_from' => fallback ? forecast_day['date'] : nil
      )
    end

    def self.normalize(data)
      data.to_h.each_with_object({}) do |(key, value), normalized|
        normalized[key.to_s] = normalize_value(value)
      end
    end

    def self.normalize_date(value)
      date = value.is_a?(Date) ? value : Date.parse(value.to_s)
      date.strftime('%Y-%m-%d')
    end
    private_class_method :normalize_date

    def self.hourly_values(hour)
      {
        'temp_c' => hour['temp_c'],
        'feelslike_c' => hour['feelslike_c'],
        'condition' => hour.dig('condition', 'text'),
        'condition_icon' => hour.dig('condition', 'icon'),
        'wind_kph' => hour['wind_kph'],
        'wind_dir' => hour['wind_dir'],
        'precip_mm' => hour['precip_mm'],
        'precip_prob' => hour['chance_of_rain'],
        'humidity' => hour['humidity'],
        'uv' => hour['uv']
      }
    end
    private_class_method :hourly_values

    def self.daily_values(day)
      {
        'temp_c' => day['avgtemp_c'],
        'feelslike_c' => day['avgtemp_c'],
        'condition' => day.dig('condition', 'text'),
        'condition_icon' => day.dig('condition', 'icon'),
        'wind_kph' => day['maxwind_kph'],
        'wind_dir' => 'N/A',
        'precip_mm' => day['totalprecip_mm'],
        'precip_prob' => day['daily_chance_of_rain'],
        'humidity' => day['avghumidity'],
        'uv' => day['uv']
      }
    end
    private_class_method :daily_values

    def self.normalize_alerts(alerts)
      values = alerts.is_a?(Hash) ? alerts['alert'] : alerts
      Array(values).map { |alert| normalize(alert) }
    end
    private_class_method :normalize_alerts

    def self.normalize_value(value)
      case value
      when Hash then normalize(value)
      when Array then value.map { |item| normalize_value(item) }
      else value
      end
    end
    private_class_method :normalize_value
  end
end
