module Bot
  module Callbacks
    class Publish < Bot::CallbackHandler
      def process
        event = get_event
        return unless event
        
        gateway = Notifications::TelegramGateway.new(@bot)
        result = Events::PublishEvent.call(
          event: event,
          actor: @user,
          gateway: gateway,
          channel_id: APP_CONFIG.public_channel_id,
          payload: publication_payload(event)
        )

        if result.success?
          schedule_weather_updates(event)
          notify_subscribers(event, gateway)
          answer_callback_query(I18n.t('event_published'))
        else
          handle_publication_failure(result, event)
        end
      end
      
      private

      def schedule_weather_updates(event)
        return unless event.weather_data.present? && APP_CONFIG.weather_enabled?

        Bot::Helpers::WeatherScheduler.schedule_weather_updates(event, bot: @bot)
      rescue => e
        AppLogger.error(
          'Bot::Callbacks::Publish',
          'Failed to schedule weather updates after publication',
          event_id: event.id,
          exception: e
        )
      end
      
      def publication_payload(event)
        event_text = Bot::Helpers::Formatter.event_info(event)
        buttons = [
          [
            create_button(
              I18n.t('buttons.join'),
              "join-#{event.id}"
            ),
            create_button(
              I18n.t('buttons.unjoin'),
              "unjoin-#{event.id}"
            )
          ]
        ]
        
        {
          text: event_text,
          parse_mode: 'HTML',
          reply_markup: create_keyboard(buttons)
        }
      end
      
      def notify_subscribers(event, gateway)
        event_text = Bot::Helpers::Formatter.event_info(event)
        buttons = [
          [
            create_button(
              I18n.t('buttons.join'),
              "join-#{event.id}"
            ),
            create_button(
              I18n.t('buttons.unjoin'),
              "unjoin-#{event.id}"
            )
          ]
        ]
        
        result = Notifications::PublishSubscribers.call(
          event: event,
          gateway: gateway,
          payload: {
            text: "🔔 <b>Новое событие!</b>\n\n#{event_text}",
            parse_mode: 'HTML',
            reply_markup: create_keyboard(buttons)
          }
        )

        AppLogger.info(
          'Bot::Callbacks::Publish',
          'Subscriber delivery completed',
          event_id: event.id,
          sent_count: result.metadata[:sent_count],
          failed_count: result.metadata.fetch(:failed_user_ids, []).count,
          error_code: result.error_code
        )
      end

      def handle_publication_failure(result, event)
        if result.error_code == :forbidden
          answer_callback_query(I18n.t('not_author'), show_alert: true)
          return
        end

        if result.error_code == :already_published
          answer_callback_query('Событие уже опубликовано', show_alert: true)
          return
        end

        AppLogger.error(
          'Bot::Callbacks::Publish',
          'Failed to publish event',
          event_id: event.id,
          error_code: result.error_code,
          exception: result.error
        )
        answer_callback_query(I18n.t('publish_error'), show_alert: true)
      end
    end
  end
end
