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
        channel_id = CONFIG['PUBLIC_CHANNEL_ID']
        return unless channel_id
        return unless event.published
        
        vars = build_event_vars(event, params)
        notification = render_template(template_key, vars)
        send_notification(channel_id, notification)
      end
      
      private
      
      def build_event_vars(event, additional_params = {})
        vars = additional_params.dup
        channel_link = event.channel_link
        puts "Event #{event.id}: channel_message_id=#{event.channel_message_id}, channel_link=#{channel_link}"
        
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
          puts "Failed to notify #{chat_id}: #{e.message}"
        end
      end
    end
  end
end