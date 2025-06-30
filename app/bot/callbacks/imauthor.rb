module Bot
  module Callbacks
    class Imauthor
      def initialize(bot, callback, session)
        @bot = bot
        @callback = callback
        @session = session
        @chat_id = callback.message.chat.id
        @message_id = callback.message.message_id
      end
      
      def process
        return unless @callback.message.chat.type == 'private'
        user = User.find_or_create_from_telegram(@callback.from)
        today = Date.today
        
        puts "DEBUG: User ID: #{user.id}, Telegram ID: #{user.telegram_id}"
        
        events = user.authored_events.where('date >= ?', today).order(date: :asc)
        
        all_events_by_user = user.authored_events
        all_events_direct = Event.where(author_id: user.id)
        all_users_with_same_telegram_id = User.where(telegram_id: user.telegram_id)
        all_events_by_telegram_id = Event.joins(:author).where(users: { telegram_id: user.telegram_id })
        
        puts "DEBUG: Events via relation: #{all_events_by_user.count} total, #{events.count} future"
        puts "DEBUG: Events via direct query: #{all_events_direct.count} total"
        puts "DEBUG: Users with same telegram_id: #{all_users_with_same_telegram_id.count}"
        puts "DEBUG: Events by telegram_id: #{all_events_by_telegram_id.count}"
        
        all_users_with_same_telegram_id.each do |u|
          puts "DEBUG: User #{u.id}, telegram_id: #{u.telegram_id}, created: #{u.created_at}"
        end
        
        all_events_by_user.each do |e|
          puts "DEBUG: Event #{e.id}, author_id: #{e.author_id}, date: #{e.date}, type: #{e.event_type}, future: #{e.date >= today}"
        end
        
        if all_events_by_telegram_id.count > all_events_by_user.count
          puts "DEBUG: Found more events by telegram_id, using alternative query"
          events = all_events_by_telegram_id.where('date >= ?', today).order(date: :asc)
        end
        
        @bot.api.delete_message(
          chat_id: @chat_id,
          message_id: @message_id
        )
        
        if events.empty?
          debug_message = "#{I18n.t('no_events')}\n\n🔍 Отладка:\n" +
                         "User ID: #{user.id}\n" +
                         "Telegram ID: #{user.telegram_id}\n" +
                         "Всего событий (прямой запрос): #{all_events_direct.count}\n" +
                         "Всего событий (через связь): #{all_events_by_user.count}\n" +
                         "Будущих событий: #{events.count}"
          @bot.api.send_message(
            chat_id: @chat_id,
            text: debug_message
          )
        else
          events.each do |event|
            message = Bot::Helpers::Formatter.event_info(event)
            
            buttons = [
              [
                Telegram::Bot::Types::InlineKeyboardButton.new(
                  text: I18n.t('buttons.edit'),
                  callback_data: "edit-#{event.id}"
                )
              ],
              [
                Telegram::Bot::Types::InlineKeyboardButton.new(
                  text: I18n.t('buttons.delete'),
                  callback_data: "delete-#{event.id}"
                )
              ],
              [
                Telegram::Bot::Types::InlineKeyboardButton.new(
                  text: I18n.t('buttons.publish'),
                  callback_data: "publish-#{event.id}"
                )
              ]
            ]
            
            markup = Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: buttons)
            @bot.api.send_message(
              chat_id: @chat_id,
              text: message,
              parse_mode: 'HTML',
              reply_markup: markup
            )
          end
        end
      end
    end
  end
end
