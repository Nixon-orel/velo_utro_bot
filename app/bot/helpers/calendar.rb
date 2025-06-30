module Bot
  module Helpers
    class Calendar
      attr_reader :chats
      attr_accessor :lock_date_array
      
      def initialize(options = {})
        @options = {
          date_format: 'YYYY-MM-DD',
          language: 'ru',
          start_week_day: 1,
          start_date: Date.today,
          stop_date: (Date.today + 6.months),
          lock_date: false
        }.merge(options)
        
        @chats = {}
        @lock_date_array = []
      end
      
      def send_to(bot, chat_id, message_text = nil)
        markup = create_calendar(@options[:start_date])
        text = message_text || I18n.t('calendar.select_date')
        message = bot.api.send_message(
          chat_id: chat_id,
          text: text,
          reply_markup: markup
        )
        
        @chats[chat_id] = message.message_id
      end
      
      def handle_callback(bot, callback)
        data = callback.data
        chat_id = callback.message.chat.id
        message_id = callback.message.message_id
        return nil unless data.start_with?('calendar')
        
        parts = data.split('_')
        action = parts[1]
        
        case action
        when 'day'
          date_str = parts[2]
          date = Date.parse(date_str)
          
          if @options[:lock_date] && !@lock_date_array.empty? && @lock_date_array.include?(date_str)
            bot.api.answer_callback_query(
              callback_query_id: callback.id,
              text: I18n.t('calendar.date_locked'),
              show_alert: true
            )
            return nil
          end
          
          bot.api.answer_callback_query(
            callback_query_id: callback.id
          )
          
          return date_str
        when 'month'
          year = parts[2].to_i
          month = parts[3].to_i
          date = Date.new(year, month, 1)
          
          markup = create_calendar(date)
          
          bot.api.edit_message_reply_markup(
            chat_id: chat_id,
            message_id: message_id,
            reply_markup: markup
          )
          
          bot.api.answer_callback_query(
            callback_query_id: callback.id
          )
          
          return nil
        end
      end
      
      private
      
      def create_calendar(date)
        year = date.year
        month = date.month
        month_names = I18n.t('date.month_names')
        day_names = I18n.t('date.abbr_day_names')
        start_week_day = @options[:start_week_day]
        day_names = day_names.rotate(start_week_day)
        keyboard = day_names.map do |day|
          Telegram::Bot::Types::InlineKeyboardButton.new(
            text: day,
            callback_data: 'calendar_ignore'
          )
        end
        
        header = [
          Telegram::Bot::Types::InlineKeyboardButton.new(
            text: "#{month_names[month]} #{year}",
            callback_data: 'calendar_ignore'
          )
        ]
        
        navigation = []
        
        prev_month = month == 1 ? 12 : month - 1
        prev_year = month == 1 ? year - 1 : year
        prev_date = Date.new(prev_year, prev_month, 1)
        
        if prev_date >= @options[:start_date]
          navigation << Telegram::Bot::Types::InlineKeyboardButton.new(
            text: '«',
            callback_data: "calendar_month_#{prev_year}_#{prev_month}"
          )
        else
          navigation << Telegram::Bot::Types::InlineKeyboardButton.new(
            text: ' ',
            callback_data: 'calendar_ignore'
          )
        end
        
        next_month = month == 12 ? 1 : month + 1
        next_year = month == 12 ? year + 1 : year
        next_date = Date.new(next_year, next_month, 1)
        
        if next_date <= @options[:stop_date]
          navigation << Telegram::Bot::Types::InlineKeyboardButton.new(
            text: '»',
            callback_data: "calendar_month_#{next_year}_#{next_month}"
          )
        else
          navigation << Telegram::Bot::Types::InlineKeyboardButton.new(
            text: ' ',
            callback_data: 'calendar_ignore'
          )
        end
        
        keyboard = [header, navigation, keyboard]
        first_day = Date.new(year, month, 1)
        last_day = Date.new(year, month, -1)
        first_weekday = first_day.wday
        first_weekday = (first_weekday - start_week_day) % 7
        day = 1
        row = []
        
        first_weekday.times do
          row << Telegram::Bot::Types::InlineKeyboardButton.new(
            text: ' ',
            callback_data: 'calendar_ignore'
          )
        end
        
        while day <= last_day.day
          date = Date.new(year, month, day)
          date_str = date.strftime('%Y-%m-%d')
          is_locked = @options[:lock_date] && !@lock_date_array.empty? && @lock_date_array.include?(date_str)
          
          button_text = day.to_s
          button_data = is_locked ? 'calendar_ignore' : "calendar_day_#{date_str}"
          
          row << Telegram::Bot::Types::InlineKeyboardButton.new(
            text: button_text,
            callback_data: button_data
          )
          
          if row.size == 7
            keyboard << row
            row = []
          end
          
          day += 1
        end
        
        if row.size > 0
          (7 - row.size).times do
            row << Telegram::Bot::Types::InlineKeyboardButton.new(
              text: ' ',
              callback_data: 'calendar_ignore'
            )
          end
          keyboard << row
        end
        
        Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: keyboard)
      end
    end
  end
end