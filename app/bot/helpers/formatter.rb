module Bot
  module Helpers
    class Formatter
      def self.format_date(date)
        weekday = I18n.l(date, format: '%A')
        capitalized_weekday = weekday.capitalize
        
        day = date.day
        month_genitive = I18n.t('date.genitive_month_names')[date.month]
        
        "#{capitalized_weekday} (#{day} #{month_genitive})"
      end
      
      def self.format_time(time)
        time.to_s[0..4]
      end
      
      def self.event_info(event)
        participants = event.participants_list
        template = I18n.t('event_info')
        Mustache.render(template, {
          title: format_date(event.date),
          event: {
            type: event.event_type,
            formatted_time: event.formatted_time,
            location: event.location,
            distance: event.distance,
            pace: event.pace,
            track: event.track,
            map: event.map,
            additional_info: event.additional_info,
            author: {
              nickname: event.author.nickname,
              username: event.author.username
            }
          },
          participants: participants
        })
      end
    end
  end
end