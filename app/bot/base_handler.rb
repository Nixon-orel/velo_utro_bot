module Bot
  class BaseHandler
    attr_reader :bot, :message, :session, :chat_id, :user
    
    def initialize(bot, message, session)
      @bot = bot
      @message = message
      @session = session
      @chat_id = get_chat_id(message)
      @user = get_user(message)
    end
    
    protected
    
    def get_chat_id(message)
      if message.respond_to?(:chat)
        message.chat.id
      elsif message.respond_to?(:message)
        message.message.chat.id
      else
        nil
      end
    end
    
    def get_message_id(message)
      if message.respond_to?(:message_id)
        message.message_id
      elsif message.respond_to?(:message)
        message.message.message_id
      else
        nil
      end
    end
    
    def get_user(message)
      user_data = extract_user_data(message)
      return nil unless user_data
      
      User.find_or_create_from_telegram(OpenStruct.new(user_data))
    end
    
    def extract_user_data(message)
      from_obj = get_from_object(message)
      return nil unless from_obj&.respond_to?(:id)
      
      {
        id: from_obj.id.to_s,
        first_name: from_obj.respond_to?(:first_name) ? from_obj.first_name : nil,
        username: from_obj.respond_to?(:username) ? from_obj.username : nil
      }
    end
    
    def get_from_object(message)
      return message.from if message.respond_to?(:from)
      return message.message.from if message.respond_to?(:message) && message.message&.respond_to?(:from)
      nil
    end
    
    def create_button(text, callback_data)
      Telegram::Bot::Types::InlineKeyboardButton.new(
        text: text,
        callback_data: callback_data
      )
    end
    
    def create_url_button(text, url)
      Telegram::Bot::Types::InlineKeyboardButton.new(
        text: text,
        url: url
      )
    end
    
    def create_keyboard(buttons)
      Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: buttons)
    end
    
    def create_reply_keyboard(buttons, options = {})
      keyboard_buttons = buttons.map do |row|
        row.map do |text|
          Telegram::Bot::Types::KeyboardButton.new(text: text)
        end
      end
      
      default_options = {
        keyboard: keyboard_buttons,
        resize_keyboard: true,
        one_time_keyboard: false
      }
      
      Telegram::Bot::Types::ReplyKeyboardMarkup.new(default_options.merge(options))
    end
    
    def remove_reply_keyboard
      Telegram::Bot::Types::ReplyKeyboardRemove.new(remove_keyboard: true)
    end
    
    def create_find_buttons
      [
        [create_button(I18n.t('buttons.find_today'), 'find_today')],
        [create_button(I18n.t('buttons.find_tomorrow'), 'find_tomorrow')],
        [create_button(I18n.t('buttons.find_week'), 'find_week')],
        [create_button(I18n.t('buttons.find_date'), 'find_date')],
        [create_button(I18n.t('buttons.find_all'), 'find_all')]
      ]
    end
    
    def create_my_events_buttons
      [
        [create_button(I18n.t('i_m_author'), 'imauthor')],
        [create_button(I18n.t('i_m_participant'), 'imparticipant')]
      ]
    end
    
    def send_button_message(text, buttons, options = {})
      markup = create_keyboard(buttons)
      send_message(text, { reply_markup: markup }.merge(options))
    end
    
    def send_message(text, options = {})
      default_options = {
        chat_id: @chat_id,
        text: text
      }
      
      @bot.api.send_message(default_options.merge(options))
    end
    
    def send_html_message(text, options = {})
      send_message(text, { parse_mode: 'HTML' }.merge(options))
    end
    
    def edit_message(text, message_id, options = {})
      default_options = {
        chat_id: @chat_id,
        message_id: message_id,
        text: text
      }
      
      @bot.api.edit_message_text(default_options.merge(options))
    end
    
    def edit_html_message(text, message_id, options = {})
      edit_message(text, message_id, { parse_mode: 'HTML' }.merge(options))
    end
    
    def answer_callback_query(text = nil, options = {})
      return unless @message.respond_to?(:id)
      
      default_options = {
        callback_query_id: @message.id
      }
      
      default_options[:text] = text if text
      
      @bot.api.answer_callback_query(default_options.merge(options))
    end
    
    def delete_message(message_id = nil)
      message_id ||= get_message_id(@message)
      return unless message_id
      
      @bot.api.delete_message(
        chat_id: @chat_id,
        message_id: message_id
      )
    end
    
    def display_events(events, title, no_events_message)
      if events.empty?
        send_message(no_events_message)
      else
        send_message("#{title}:")
        
        events.each do |event|
          message = Bot::Helpers::Formatter.event_info(event)
          is_participant = event.has_participant?(@user)
          
          buttons = [
            [
              create_button(
                is_participant ? I18n.t('buttons.unjoin') : I18n.t('buttons.join'),
                is_participant ? "unjoin-#{event.id}" : "join-#{event.id}"
              )
            ]
          ]
          
          if @user&.admin?
            buttons << [
              create_button(
                I18n.t('buttons.publish'),
                "publish-#{event.id}"
              )
            ]
          end
          
          markup = create_keyboard(buttons)
          send_html_message(message, { reply_markup: markup })
        end
      end
    end
    
    def update_event_message(event, message_id = nil)
      message_id ||= get_message_id(@message)
      return unless message_id
      
      channel_id = CONFIG['PUBLIC_CHANNEL_ID']
      if channel_id && @chat_id.to_s == channel_id.to_s
        update_channel_event_message(event, message_id)
        return
      end
      
      message = Bot::Helpers::Formatter.event_info(event)
      buttons = []
      
      if @chat_id.to_s == @user&.telegram_id
        is_participant = event.has_participant?(@user)
        buttons << [
          create_button(
            is_participant ? I18n.t('buttons.unjoin') : I18n.t('buttons.join'),
            is_participant ? "unjoin-#{event.id}" : "join-#{event.id}"
          )
        ]
        
        if @user&.admin?
          buttons << [
            create_button(
              I18n.t('buttons.publish'),
              "publish-#{event.id}"
            )
          ]
        end
      else
        is_participant = event.has_participant?(@user)
        buttons << [
          create_button(
            is_participant ? I18n.t('buttons.unjoin') : I18n.t('buttons.join'),
            is_participant ? "unjoin-#{event.id}" : "join-#{event.id}"
          )
        ]
      end
      
      markup = create_keyboard(buttons)
      edit_html_message(message, message_id, { reply_markup: markup })
    end
    
    def update_channel_event_message(event, message_id)
      message = Bot::Helpers::Formatter.event_info(event)
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
      
      markup = create_keyboard(buttons)
      edit_html_message(message, message_id, { reply_markup: markup })
    end
  end
end