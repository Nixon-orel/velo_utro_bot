module Bot
  module Helpers
    class Statistics
      def initialize(bot = nil)
        @bot = bot
      end
      
      def monthly_report(month = nil, year = nil)
        previous_month = AppClock.today - 1.month
        month ||= previous_month.month
        year ||= previous_month.year
        
        start_date = Date.new(year, month, 1)
        end_date = start_date.end_of_month
        
        events = Event.includes(:author, :participants)
                     .where(date: start_date..end_date)
                     .to_a
        
        {
          period: "#{I18n.t('date.month_names')[month]} #{year}",
          total_events: count_created_events(events),
          bike_events: count_bike_events(events),
          other_events: count_other_events_by_type(events),
          total_kilometers: calculate_total_distance(events),
          top_organizer: find_top_organizer(events),
          most_active_participant: find_most_active_participant(events)
        }
      end
      
      def format_monthly_report(data)
        report = []
        report << "📊 <b>Статистика велобота за #{data[:period]}:</b>\n"
        report << "🚴 Создано велособытий: <b>#{data[:bike_events]}</b>"

        if data[:total_kilometers] > 0
          report << "\n🚴‍♂️ Прокатано километров: <b>#{data[:total_kilometers]} км</b>"
        end
        
        if data[:other_events].any?
          report << "\n📌 Другие события:"
          data[:other_events].each do |type, count|
            report << "  • #{type}: #{count}"
          end
        end
        
        if data[:top_organizer]
          report << "\n🎉 Главный массовик-затейник месяца:"
          report << "  #{data[:top_organizer][:display_name]} (создано #{data[:top_organizer][:count]} #{pluralize_events(data[:top_organizer][:count])})"
        end
        
        if data[:most_active_participant]
          report << "\n💫 Душа компании месяца:"
          report << "  #{data[:most_active_participant][:display_name]} (участвовал(а) в #{data[:most_active_participant][:count]} #{pluralize_events(data[:most_active_participant][:count])})"
        end
        
        report << "\n\n💪 Присоединяйтесь к нашему дружному сообществу пользователей бота!"
        report << "Вместе мы делаем этот мир активнее и веселее! 🚴‍♀️🎉"
        
        report.join("\n")
      end
      
      def send_monthly_report
        unless @bot
          AppLogger.warn('Bot::Helpers::Statistics', 'Bot instance is missing')
          return false
        end
        
        unless APP_CONFIG.public_channel_id
          AppLogger.warn('Bot::Helpers::Statistics', 'Public channel is not configured')
          return false
        end
        
        AppLogger.info('Bot::Helpers::Statistics', 'Generating monthly report')
        data = monthly_report
        
        AppLogger.debug(
          'Bot::Helpers::Statistics',
          'Monthly report generated',
          bike_events: data[:bike_events],
          total_events: data[:total_events],
          period: data[:period]
        )
        message = format_monthly_report(data)
        
        @bot.api.send_message(
          chat_id: APP_CONFIG.public_channel_id,
          text: message,
          parse_mode: 'HTML'
        )
        AppLogger.info('Bot::Helpers::Statistics', 'Monthly report sent')
        true
      rescue => e
        AppLogger.error('Bot::Helpers::Statistics', 'Failed to send monthly report', exception: e)
        false
      end
      
      private
      
      def count_created_events(events)
        events.count
      end
      
      def count_bike_events(events)
        events.count { |event| event.event_type&.include?('Велосипед') }
      end
      
      def count_other_events_by_type(events)
        events.reject { |e| e.event_type&.include?('Велосипед') }
              .group_by(&:event_type)
              .transform_values(&:count)
              .sort_by { |_, count| -count }
              .to_h
      end
      
      def calculate_total_distance(events)
        total = 0
        
        events.each do |event|
          next unless event.distance
          
          distance = event.distance.to_s.strip
          match = distance.match(/([0-9]+)\s*(?:км|km)/i) || distance.match(/\A([0-9]+)/)
          total += match[1].to_i if match
        end
        
        total
      end
      
      def find_top_organizer(events)
        return nil if events.empty?
        
        author, authored_events = events.group_by(&:author).max_by { |_, values| values.count }
        return nil unless author
        
        {
          display_name: author.display_name,
          count: authored_events.count
        }
      end
      
      def find_most_active_participant(events)
        return nil if events.empty?
        
        participants = events.flat_map { |event| event.participants.to_a }
        participant_counts = participants.tally
        
        return nil if participant_counts.empty?
        
        user, count = participant_counts.max_by { |_, value| value }
        
        {
          display_name: user.display_name,
          count: count
        }
      end
      
      def pluralize_events(count)
        case count % 10
        when 1
          count % 100 == 11 ? "событий" : "событие"
        when 2, 3, 4
          [12, 13, 14].include?(count % 100) ? "событий" : "события"
        else
          "событий"
        end
      end
    end
  end
end
