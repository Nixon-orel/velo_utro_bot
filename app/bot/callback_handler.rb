module Bot
  class CallbackHandler < BaseHandler
    attr_reader :callback_data, :message_id
    
    def initialize(bot, callback, session)
      super
      @callback_data = callback.data
      @message_id = callback.message.message_id if callback.message
    end
    
    def process
      raise NotImplementedError, "#{self.class} должен реализовать метод #process"
    end
    
    def ensure_private_chat
      return true if @message.message.chat.type == 'private'
      
      false
    end
    
    def get_event_id
      @callback_data.split('-')[1] if @callback_data.include?('-')
    end
    
    def get_event
      event_id = get_event_id
      return nil unless event_id

      event = Event.find_by(id: event_id)
      return event if event

      answer_callback_query(I18n.t('invalid_input'), show_alert: true)
      nil
    end

    def get_authorized_event
      event = get_event
      return unless event
      return event if Events::Policy.manage?(event: event, actor: @user)

      answer_callback_query(I18n.t('not_author'), show_alert: true)
      nil
    end

    def prepare_event_edit(event, state, calendar_type: nil)
      @session.edit_event_id = event.id
      @session.state = state
      @session.calendar_type = calendar_type if calendar_type
      @session.save_session
    end
  end
end
