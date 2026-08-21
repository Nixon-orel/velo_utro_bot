module Bot
  class UpdateRouter
    def initialize(bot)
      @bot = bot
    end

    def call(update)
      case update
      when Telegram::Bot::Types::Message
        handle_message(update)
      when Telegram::Bot::Types::CallbackQuery
        handle_callback(update)
      end
    rescue => e
      AppLogger.error('Bot::UpdateRouter', 'Failed to process update', exception: e)
    end

    private

    def handle_message(message)
      return unless message.from

      session = Session.load(message.from.id.to_s)

      if message.text&.start_with?('/')
        handle_command(message, session)
      elsif session.state
        return unless private_chat?(message.chat)

        Bot::States.process(session.state, @bot, message, session)
      elsif private_chat?(message.chat)
        @bot.api.send_message(chat_id: message.chat.id, text: I18n.t('unknown_command'))
      end
    end

    def handle_command(message, session)
      command = message.text.split(' ').first[1..].split('@').first

      if private_chat?(message.chat)
        Bot::Commands.execute(command, @bot, message, session)
      else
        redirect_command_to_private_chat(message, command)
      end
    end

    def redirect_command_to_private_chat(message, command)
      bot_username = APP_CONFIG.bot_username

      if bot_username && !bot_username.empty?
        button = Telegram::Bot::Types::InlineKeyboardButton.new(
          text: '💬 Открыть чат с ботом',
          url: "https://t.me/#{bot_username}?start=#{command}"
        )
        markup = Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: [[button]])

        @bot.api.send_message(
          chat_id: message.chat.id,
          text: 'Для использования команд бота перейдите в личные сообщения:',
          reply_markup: markup
        )
      else
        username = @bot.api.get_me['result']['username']
        @bot.api.send_message(
          chat_id: message.chat.id,
          text: "Для использования команд бота перейдите в личные сообщения с @#{username}"
        )
      end
    end

    def handle_callback(callback)
      return unless callback.from

      session = callback_session(callback)
      return unless session

      if callback.data.start_with?('calendar')
        handle_calendar_callback(callback, session)
      elsif callback.data.include?('-')
        Bot::Callbacks.process(callback.data, @bot, callback, session)
      else
        handle_event_type_callback(callback, session)
      end
    end

    def callback_session(callback)
      return Session.load(callback.from.id.to_s) if private_chat?(callback.message.chat)

      action = callback.data.split('-')[0]
      return unless %w[join unjoin].include?(action)

      OpenStruct.new(data: {})
    end

    def handle_calendar_callback(callback, session)
      result = Bot::Helpers::Calendar.new.handle_callback(@bot, callback)
      return unless result

      case session.state
      when 'choose_date'
        select_event_date(callback, session, result)
      when 'edit_date'
        edit_event_date(callback, session, result)
      when 'find_events_on_date'
        display_events_for_date(callback, session, result)
      end
    end

    def select_event_date(callback, session, date)
      session.new_event['date'] = date
      session.state = 'choose_time'
      session.save_session

      @bot.api.send_message(
        chat_id: callback.message.chat.id,
        text: I18n.t('choose_time'),
        parse_mode: 'HTML'
      )
    end

    def edit_event_date(callback, session, date)
      event = Event.find_by(id: session.edit_event_id)
      user = User.find_or_create_from_telegram(callback.from)
      return unless event

      result = Events::EditEvent.call(event: event, actor: user, changes: { date: Date.parse(date) })
      return unless result.success?

      new_date = event.formatted_date

      notifier = Bot::Helpers::Notifier.new(@bot)
      notifier.notify_participants(event, 'date_changed_notification', { new_date: new_date })
      notifier.notify_channel_about_change(event, 'date_changed_channel_notification', { new_date: new_date })

      if event.weather_data.present? && APP_CONFIG.weather_enabled?
        Bot::Helpers::WeatherScheduler.schedule_weather_updates(event)
        AppLogger.info('Bot::UpdateRouter', 'Rescheduled weather updates', event_id: event.id)
      end

      session.state = nil
      session.edit_event_id = nil
      session.save_session

      send_html(callback.message.chat.id, I18n.t('date_saved'))
      send_html(callback.message.chat.id, I18n.t('event_updated'))
    end

    def display_events_for_date(callback, session, selected_date)
      date = Date.parse(selected_date)
      events = Event.on_date(date)
      handler = Bot::CallbackHandler.new(@bot, callback, session)
      handler.send(
        :display_events,
        events,
        I18n.t('buttons.find_date'),
        I18n.t('no_upcoming_events')
      )
    end

    def handle_event_type_callback(callback, session)
      event_type = callback.data

      unless APP_CONFIG.event_types.include?(event_type)
        Bot::Callbacks.process(callback.data, @bot, callback, session)
        return
      end

      session.new_event['type'] = event_type
      session.state = 'choose_location'
      session.save_session

      send_html(callback.message.chat.id, I18n.t('choose_location'))
    end

    def send_html(chat_id, text)
      @bot.api.send_message(chat_id: chat_id, text: text, parse_mode: 'HTML')
    end

    def private_chat?(chat)
      chat.type == 'private'
    end
  end
end
