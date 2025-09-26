module Bot
  module Helpers
    class Statistics
      def initialize(bot = nil)
        @bot = bot
      end
      
      def monthly_report(month = nil, year = nil)
        month ||= (Date.today - 1.month).month
        year ||= (Date.today - 1.month).year
        
        start_date = Date.new(year, month, 1)
        end_date = start_date.end_of_month
        
        events = Event.includes(:author, :participants)
                     .where(date: start_date..end_date)
        
        {
          period: "#{I18n.t('date.month_names')[month]} #{year}",
          total_events: count_created_events(events),
          bike_events: count_bike_events(events),
          other_events: count_other_events_by_type(events),
          cancelled_events: count_cancelled_events(start_date, end_date),
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
        
        if data[:cancelled_events] > 0
          report << "\n❌ Событий отменено: <b>#{data[:cancelled_events]}</b>"
        end
        
        if data[:top_organizer]
          report << "\n🎉 Главный массовик-затейник месяца:"
          report << "  @#{data[:top_organizer][:nickname]} (создал #{data[:top_organizer][:count]} #{pluralize_events(data[:top_organizer][:count])})"
        end
        
        if data[:most_active_participant]
          report << "\n💫 Душа компании месяца:"
          report << "  @#{data[:most_active_participant][:nickname]} (участвовал в #{data[:most_active_participant][:count]} #{pluralize_events(data[:most_active_participant][:count])})"
        end
        
        report << "\n\n💪 Присоединяйтесь к нашему дружному сообществу пользователей бота!"
        report << "Вместе мы делаем этот мир активнее и веселее! 🚴‍♀️🎉"
        
        report.join("\n")
      end
      
      def send_monthly_report
        return unless @bot && ENV['PUBLIC_CHANNEL_ID']
        
        data = monthly_report
        message = format_monthly_report(data)
        
        @bot.api.send_message(
          chat_id: ENV['PUBLIC_CHANNEL_ID'],
          text: message,
          parse_mode: 'HTML'
        )
      rescue => e
        puts "Error sending monthly statistics: #{e.message}"
      end
      
      private
      
      def count_created_events(events)
        events.count
      end
      
      def count_bike_events(events)
        events.select { |e| e.event_type&.include?('Велосипед') }.count
      end
      
      def count_other_events_by_type(events)
        events.reject { |e| e.event_type&.include?('Велосипед') }
              .group_by(&:event_type)
              .transform_values(&:count)
              .sort_by { |_, count| -count }
              .to_h
      end
      
      def count_cancelled_events(start_date, end_date)
        return 0
      end
      
      def calculate_total_distance(events)
        total = 0
        
        events.each do |event|
          next unless event.distance
          
          distance_str = event.distance.to_s.strip
          
          match = distance_str.match(/(\d+)\s*(км|km|Км|КМ)/i)
          if match
            total += match[1].to_i
          elsif distance_str.match(/^\d+$/)
            total += distance_str.to_i
          elsif distance_str.match(/^(\d+)/)
            total += $1.to_i
          end
        end
        
        total
      end
      
      def find_top_organizer(events)
        return nil if events.empty?
        
        author_counts = events.group_by(&:author_id)
                              .transform_values(&:count)
                              .sort_by { |_, count| -count }
                              .first
        
        return nil unless author_counts
        
        author = User.find_by(id: author_counts[0])
        return nil unless author
        
        {
          nickname: author.nickname || author.username || "Пользователь",
          count: author_counts[1]
        }
      end
      
      def find_most_active_participant(events)
        return nil if events.empty?
        
        participant_counts = {}
        
        events.each do |event|
          event.participants.each do |participant|
            participant_counts[participant.id] ||= 0
            participant_counts[participant.id] += 1
          end
        end
        
        return nil if participant_counts.empty?
        
        top_participant = participant_counts.sort_by { |_, count| -count }.first
        user = User.find_by(id: top_participant[0])
        return nil unless user
        
        {
          nickname: user.nickname || user.username || "Пользователь",
          count: top_participant[1]
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