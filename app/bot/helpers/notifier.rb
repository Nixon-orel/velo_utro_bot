module Bot
  module Helpers
    class Notifier
      def initialize(bot)
        @bot = bot
      end
    
      def notify_participants(event, template_key, params = {})
        participants = event.participants
        vars = build_event_vars(event, params)
        notification = render_template(template_key, vars)
        
        participants.each do |participant|
          send_notification(participant.telegram_id, notification)
        end
      end
      
      def notify_author(event, user, template_key)
        author = event.author
        vars = build_event_vars(event).merge(
          user: {
            nickname: user.nickname,
            username: user.username
          }
        )
        
        notification = render_template(template_key, vars)
        send_notification(author.telegram_id, notification)
      end
      
      def notify_channel_about_change(event, template_key, params = {})
        channel_id = APP_CONFIG.public_channel_id
        return unless channel_id
        return unless event.published
        
        vars = build_event_vars(event, params)
        notification = render_template(template_key, vars)
        send_notification(channel_id, notification)
      end

      def refresh_channel_event(event)
        channel_id = APP_CONFIG.public_channel_id
        return if channel_id.to_s.empty?
        return unless event.published && event.channel_message_id

        @bot.api.edit_message_text(
          chat_id: channel_id,
          message_id: event.channel_message_id,
          text: Bot::Helpers::Formatter.event_info(event),
          parse_mode: 'HTML',
          reply_markup: channel_participation_markup(event)
        )
      rescue => e
        AppLogger.error(
          'Bot::Helpers::Notifier',
          'Failed to refresh channel event message',
          event_id: event.id,
          channel_message_id: event.channel_message_id,
          exception: e
        )
      end
      
      private

      def channel_participation_markup(event)
        buttons = [
          Telegram::Bot::Types::InlineKeyboardButton.new(
            text: I18n.t('buttons.join'),
            callback_data: "join-#{event.id}"
          ),
          Telegram::Bot::Types::InlineKeyboardButton.new(
            text: I18n.t('buttons.unjoin'),
            callback_data: "unjoin-#{event.id}"
          )
        ]

        Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: [buttons])
      end
      
      def build_event_vars(event, additional_params = {})
        vars = additional_params.dup
        channel_link = event.channel_link
        AppLogger.debug(
          'Bot::Helpers::Notifier',
          'Built event notification variables',
          event_id: event.id,
          channel_message_id: event.channel_message_id,
          channel_link: channel_link
        )
        
        vars[:event] = {
          event_type: event.event_type,
          formatted_date: event.formatted_date,
          formatted_time: event.formatted_time,
          location: event.location,
          distance: event.distance,
          pace: event.pace,
          track: event.track,
          map: event.map,
          additional_info: event.additional_info,
          channel_link: channel_link,
          author: {
            display_name: event.author.display_name
          }
        }
        vars
      end
      
      def render_template(template_key, vars)
        template = I18n.t(template_key)
        Mustache.render(template, vars)
      end
      
      def send_notification(chat_id, notification)
        begin
          @bot.api.send_message(
            chat_id: chat_id,
            text: notification,
            parse_mode: 'HTML'
          )
        rescue => e
          AppLogger.error(
            'Bot::Helpers::Notifier',
            'Failed to send notification',
            chat_id: chat_id,
            exception: e
          )
        end
      end
    end
  end
end
