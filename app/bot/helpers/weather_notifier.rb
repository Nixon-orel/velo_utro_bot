require 'digest'
require 'json'

module Bot
  module Helpers
    class WeatherNotifier
      WEATHER_NOTIFICATION_PREFIX = 'weather.'.freeze
      DELIVERY_KEYS = %w[critical_3d critical_24h 3d_accurate 2h_channel].freeze
      USER_DELIVERY_KEYS = %w[critical_3d critical_24h 3d_accurate].freeze
      CHANNEL_REFRESH_PREFIX = 'channel_refresh_'.freeze
      PreparedUpdate = Struct.new(:deliveries, keyword_init: true)

      class << self
        def context_key(event)
          values = [
            event.weather_schedule_revision,
            event.starts_at&.utc&.iso8601,
            event.latitude,
            event.longitude
          ]
          Digest::SHA256.hexdigest(values.map(&:to_s).join('|'))
        end

        def delivery_context_key(event, delivery_key)
          content = case delivery_key
          when '2h_channel'
            [
              event.event_type,
              event.formatted_date,
              event.formatted_time,
              event.location,
              event.weather_updated_at&.iso8601
            ]
          else
            Bot::Helpers::Formatter.event_info(event) if delivery_key.start_with?(CHANNEL_REFRESH_PREFIX)
          end
          return context_key(event) unless content

          Digest::SHA256.hexdigest(JSON.generate([context_key(event), content]))
        end

        def delivery_current?(delivery)
          event = delivery.event
          starts_at = event&.starts_at
          delivery_key = delivery.notification_type.delete_prefix(WEATHER_NOTIFICATION_PREFIX)
          current_context = event&.published? && starts_at && starts_at > AppClock.now &&
            delivery_context_key(event, delivery_key) == delivery.context_key
          return false unless current_context
          return false unless recipient_current?(delivery, event, delivery_key)
          return true unless delivery.operation == 'edit_message_text'

          delivery.payload['message_id'].to_s == event.channel_message_id.to_s &&
            delivery.payload['text'] == Bot::Helpers::Formatter.event_info(event)
        end

        private

        def recipient_current?(delivery, event, delivery_key)
          return true unless USER_DELIVERY_KEYS.include?(delivery_key)
          return false unless delivery.recipient_id
          return true if delivery.recipient_id == event.author_id

          event.participants.where(id: delivery.recipient_id).exists?
        end
      end

      def initialize(bot)
        @gateway = Notifications::TelegramGateway.new(bot)
        @outbox_processor = Notifications::OutboxProcessor.new(
          gateway: @gateway,
          delivery_guard: self.class.method(:delivery_current?),
          notification_type_prefix: WEATHER_NOTIFICATION_PREFIX
        )
      end

      def process_pending_deliveries(limit: 100)
        deliveries = @outbox_processor.process_due(limit: limit)
        finalize_processed_deliveries(deliveries)
        reconcile_delivered_stages
        deliveries
      end

      def prepare_update(event, update_type, old_weather: nil, new_weather:)
        return unless event && new_weather

        old_weather = Weather::Forecast.normalize(old_weather)
        new_weather = Weather::Forecast.normalize(new_weather)

        case update_type
        when '3d' then prepare_3d_update(event, old_weather, new_weather)
        when '24h' then prepare_24h_update(event, old_weather, new_weather)
        when '2h' then prepare_channel_weather_forecast(event, new_weather)
        else PreparedUpdate.new(deliveries: [])
        end
      end

      def deliver_prepared_update(event, prepared_update)
        return [] unless prepared_update

        process_deliveries(prepared_update.deliveries)
      end

      def handle_3d_weather_update(event, old_weather, new_weather)
        prepared_update = prepare_update(
          event,
          '3d',
          old_weather: old_weather,
          new_weather: new_weather
        )
        deliver_prepared_update(event, prepared_update)
      end
      
      def handle_24h_weather_update(event, old_weather, new_weather)
        prepared_update = prepare_update(
          event,
          '24h',
          old_weather: old_weather,
          new_weather: new_weather
        )
        deliver_prepared_update(event, prepared_update)
      end
      
      def handle_2h_weather_update(event, weather_data)
        prepared_update = prepare_update(event, '2h', new_weather: weather_data)
        deliver_prepared_update(event, prepared_update)
      end
      
      private
      
      def weather_changed_critically?(old_weather, new_weather)
        return false if old_weather.empty?
        
        temp_change = (new_weather['temp_c'].to_f - old_weather['temp_c'].to_f).abs
        
        old_precip = old_weather['precip_prob'].to_i > 50
        new_precip = new_weather['precip_prob'].to_i > 50
        precip_change = old_precip != new_precip
        
        wind_change = (new_weather['wind_kph'].to_f - old_weather['wind_kph'].to_f).abs > 15
        
        alerts_appeared = !new_weather['alerts'].to_a.empty? && old_weather['alerts'].to_a.empty?
        
        temp_change > 5 || precip_change || wind_change || alerts_appeared
      end
      
      def prepare_3d_update(event, old_weather, new_weather)
        if old_weather && old_weather['is_fallback']
          prepare_accurate_weather_update(event, old_weather, new_weather)
        elsif weather_changed_critically?(old_weather, new_weather)
          prepare_critical_weather_alerts(event, old_weather, new_weather, 'critical_3d')
        else
          prepare_channel_refresh(event, 'channel_refresh_3d')
        end
      end

      def prepare_24h_update(event, old_weather, new_weather)
        if weather_changed_critically?(old_weather, new_weather)
          prepare_critical_weather_alerts(event, old_weather, new_weather, 'critical_24h')
        else
          prepare_channel_refresh(event, 'channel_refresh_24h')
        end
      end

      def prepare_critical_weather_alerts(event, old_weather, new_weather, delivery_key)
        return PreparedUpdate.new(deliveries: []) if notification_delivered?(event, delivery_key)

        require_relative '../../services/weather_recommendations'
        
        message = format_critical_change_message(event, old_weather, new_weather)
        all_users = ([event.author] + event.participants).uniq
        deliveries = enqueue_user_deliveries(event, delivery_key, all_users, message)
        PreparedUpdate.new(deliveries: deliveries)
      end
      
      def prepare_accurate_weather_update(event, old_weather, new_weather)
        if notification_delivered?(event, '3d_accurate')
          return PreparedUpdate.new(deliveries: [])
        end

        require_relative '../../services/weather_recommendations'
        
        message = format_accurate_weather_message(event, old_weather, new_weather)
        all_users = ([event.author] + event.participants).uniq
        deliveries = enqueue_user_deliveries(event, '3d_accurate', all_users, message)
        refresh = prepare_channel_refresh(event, 'channel_refresh_3d_accurate')
        PreparedUpdate.new(deliveries: deliveries + refresh.deliveries)
      end
      
      def prepare_channel_weather_forecast(event, weather_data)
        require_relative '../../services/weather_recommendations'
        return PreparedUpdate.new(deliveries: []) unless event.published?
        return PreparedUpdate.new(deliveries: []) if notification_delivered?(event, '2h_channel')
        
        channel_id = APP_CONFIG.public_channel_id
        return PreparedUpdate.new(deliveries: []) unless channel_id
        
        recommendations = WeatherRecommendations.generate(weather_data, event.time)
        weather_info = format_weather_info(weather_data, recommendations)
        
        message = render_weather_template('weather.channel_forecast_message',
          event_type: event.event_type,
          date: event.formatted_date,
          time: event.formatted_time,
          location: event.location,
          weather_info: weather_info
        )
        
        deliveries = Notifications::Outbox.enqueue!([
          delivery_attributes(
            event: event,
            delivery_key: '2h_channel',
            recipient_key: "channel:#{channel_id}",
            chat_id: channel_id,
            payload: { text: message, parse_mode: 'HTML' }
          )
        ])
        PreparedUpdate.new(deliveries: deliveries)
      end

      def prepare_channel_refresh(event, delivery_key)
        channel_id = APP_CONFIG.public_channel_id
        unless event.channel_message_id && channel_id
          return PreparedUpdate.new(deliveries: [])
        end

        deliveries = Notifications::Outbox.enqueue!([
          delivery_attributes(
            event: event,
            delivery_key: delivery_key,
            recipient_key: "channel:#{channel_id}",
            chat_id: channel_id,
            operation: 'edit_message_text',
            payload: {
              message_id: event.channel_message_id,
              text: Bot::Helpers::Formatter.event_info(event),
              parse_mode: 'HTML'
            }
          )
        ])
        PreparedUpdate.new(deliveries: deliveries)
      end
      
      def format_critical_change_message(event, old_weather, new_weather)
        require_relative '../../services/weather_recommendations'
        
        old_condition = old_weather['condition'] || 'Неизвестно'
        old_temp = old_weather['temp_c'] || 'N/A'
        
        new_condition = new_weather['condition']
        new_temp = new_weather['temp_c']
        new_wind = new_weather['wind_kph']
        new_precip = new_weather['precip_prob']
        
        recommendations = WeatherRecommendations.generate(new_weather, event.time)
        
        message = render_weather_template('weather.critical_change_header',
          event_type: event.event_type,
          date: event.formatted_date,
          time: event.formatted_time
        )
        
        message += "\n\n#{I18n.t('weather.was')}: #{old_condition}, #{old_temp}°C"
        message += "\n#{I18n.t('weather.became')}: #{new_condition}, #{new_temp}°C"
        
        if new_wind && new_wind > 10
          message += ", ветер #{new_wind} км/ч"
        end
        
        if new_precip && new_precip > 30
          message += ", осадки #{new_precip}%"
        end
        
        if recommendations.any?
          message += "\n\n#{I18n.t('weather.recommendations')}:"
          recommendations.first(4).each { |rec| message += "\n• #{rec}" }
        end
        
        message
      end
      
      def format_accurate_weather_message(event, old_weather, new_weather)
        require_relative '../../services/weather_recommendations'
        
        recommendations = WeatherRecommendations.generate(new_weather, event.time)
        
        message = render_weather_template('weather.accurate_update_header',
          event_type: event.event_type,
          date: event.formatted_date,
          time: event.formatted_time
        )
        
        fallback_date = old_weather['fallback_from'] || 'неизвестной даты'
        message += "\n\n📅 Ранее: приблизительный прогноз (данные за #{fallback_date})"
        
        new_condition = new_weather['condition']
        new_temp = new_weather['temp_c']
        new_wind = new_weather['wind_kph']
        new_precip = new_weather['precip_prob']
        
        message += "\n🎯 Сейчас: точный прогноз - #{new_condition}, #{new_temp}°C"
        
        if new_wind && new_wind > 10
          message += ", ветер #{new_wind} км/ч"
        end
        
        if new_precip && new_precip > 30
          message += ", осадки #{new_precip}%"
        end
        
        if recommendations.any?
          message += "\n\n⚡ Рекомендации:"
          recommendations.first(4).each { |rec| message += "\n• #{rec}" }
        end
        
        message
      end
      
      def format_weather_info(weather_data, recommendations)
        temp = weather_data['temp_c']
        feels_like = weather_data['feelslike_c']
        condition = weather_data['condition']
        wind_speed = weather_data['wind_kph']
        precip_prob = weather_data['precip_prob']
        
        weather_text = "🌤️ #{condition}, #{temp}°C"
        weather_text += " (ощущ. #{feels_like}°C)" if feels_like && feels_like != temp
        weather_text += "\n💨 Ветер: #{wind_speed} км/ч" if wind_speed
        weather_text += "\n☔ Вероятность осадков: #{precip_prob}%" if precip_prob
        
        if recommendations.any?
          weather_text += "\n\n⚡ Рекомендации:"
          recommendations.first(3).each { |rec| weather_text += "\n• #{rec}" }
        end
        
        weather_text
      end
      
      def enqueue_user_deliveries(event, delivery_key, users, message)
        Notifications::Outbox.enqueue!(
          users.map do |user|
            delivery_attributes(
              event: event,
              delivery_key: delivery_key,
              recipient_key: "user:#{user.id}",
              recipient: user,
              chat_id: user.telegram_id,
              payload: { text: message, parse_mode: 'HTML' }
            )
          end
        )
      end

      def delivery_attributes(
        event:,
        delivery_key:,
        recipient_key:,
        chat_id:,
        payload:,
        recipient: nil,
        operation: 'send_message'
      )
        context_key = self.class.delivery_context_key(event, delivery_key)
        {
          event: event,
          recipient: recipient,
          notification_type: "#{WEATHER_NOTIFICATION_PREFIX}#{delivery_key}",
          context_key: context_key,
          idempotency_key: "weather:#{event.id}:#{context_key}:#{delivery_key}:#{recipient_key}",
          operation: operation,
          chat_id: chat_id,
          payload: payload
        }
      end

      def process_deliveries(deliveries)
        return [] if deliveries.empty?

        processed = @outbox_processor.process_due(ids: deliveries.map(&:id), limit: deliveries.length)
        finalize_processed_deliveries(deliveries)
        processed
      end

      def finalize_processed_deliveries(deliveries)
        deliveries.map do |delivery|
          [delivery.event_id, delivery.notification_type, delivery.context_key]
        end.uniq.each do |event_id, type, context_key|
          delivery_key = type.delete_prefix(WEATHER_NOTIFICATION_PREFIX)
          unless DELIVERY_KEYS.include?(delivery_key)
            finalize_delivery_records(event_id, type, context_key)
            next
          end

          event = Event.find_by(id: event_id)
          finalize_delivery_stage(event, delivery_key, context_key) if event
        end
      end

      def finalize_delivery_records(event_id, type, context_key)
        finalized_at = AppClock.now
        NotificationDelivery.where(
          event_id: event_id,
          notification_type: type,
          context_key: context_key,
          status: 'delivered',
          finalized_at: nil
        ).update_all(finalized_at: finalized_at, updated_at: finalized_at)
      end

      def finalize_delivery_stage(event, delivery_key, context_key)
        deliveries = NotificationDelivery.where(
          event: event,
          notification_type: "#{WEATHER_NOTIFICATION_PREFIX}#{delivery_key}",
          context_key: context_key
        )
        return unless deliveries.exists?
        return if deliveries.where(status: %w[pending processing]).exists?

        finalized_at = AppClock.now
        terminal_deliveries = deliveries.where(status: %w[failed cancelled])
        if terminal_deliveries.exists?
          deliveries.where(status: 'delivered').update_all(
            finalized_at: finalized_at,
            updated_at: finalized_at
          )
          AppLogger.warn(
            'Bot::Helpers::WeatherNotifier',
            'Weather notification stage finished with terminal delivery failures',
            event_id: event.id,
            delivery_key: delivery_key,
            failed_count: terminal_deliveries.where(status: 'failed').count,
            cancelled_count: terminal_deliveries.where(status: 'cancelled').count
          )
          return
        end

        unless self.class.delivery_context_key(event, delivery_key) == context_key
          deliveries.update_all(finalized_at: finalized_at, updated_at: finalized_at)
          return
        end

        event.with_lock do
          event.reload
          alerts = event.weather_alerts_sent.to_h
          unless alerts.key?(delivery_key)
            event.update!(weather_alerts_sent: alerts.merge(delivery_key => finalized_at.to_s))
          end
        end
        deliveries.update_all(finalized_at: finalized_at, updated_at: finalized_at)

        AppLogger.info(
          'Bot::Helpers::WeatherNotifier',
          'Weather notification stage delivered',
          event_id: event.id,
          delivery_key: delivery_key
        )
      end

      def render_weather_template(key, values)
        Mustache.render(I18n.t(key), values)
      end

      def notification_delivered?(event, key)
        type = "#{WEATHER_NOTIFICATION_PREFIX}#{key}"
        context_key = self.class.delivery_context_key(event, key)
        current_deliveries = NotificationDelivery.where(
          event: event,
          notification_type: type,
          context_key: context_key
        )
        return !current_deliveries.where.not(status: 'delivered').exists? if current_deliveries.exists?
        return false if NotificationDelivery.where(event: event, notification_type: type).exists?
        return false unless event.weather_schedule_revision.zero?

        Event.where(id: event.id).pick(:weather_alerts_sent).to_h.key?(key)
      end

      def reconcile_delivered_stages
        types = DELIVERY_KEYS.map { |key| "#{WEATHER_NOTIFICATION_PREFIX}#{key}" }
        unfinalized = NotificationDelivery.where(
          "notification_type LIKE ?",
          "#{WEATHER_NOTIFICATION_PREFIX}%"
        ).where(status: 'delivered', finalized_at: nil)
        finalized_at = AppClock.now
        unfinalized.where.not(notification_type: types).update_all(
          finalized_at: finalized_at,
          updated_at: finalized_at
        )

        seen_stages = {}
        deliveries = unfinalized.where(notification_type: types)
        deliveries.find_each(batch_size: 100) do |delivery|
          event_id = delivery.event_id
          type = delivery.notification_type
          context_key = delivery.context_key
          stage = [event_id, type, context_key]
          next if seen_stages.key?(stage)

          seen_stages[stage] = true
          event = Event.find_by(id: event_id)
          next unless event

          finalize_delivery_stage(
            event,
            type.delete_prefix(WEATHER_NOTIFICATION_PREFIX),
            context_key
          )
        end
      end

    end
  end
end
