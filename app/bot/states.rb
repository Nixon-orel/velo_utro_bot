require_relative 'base_handler'
require_relative 'state_handler'

module Bot
  module States
    Dir[File.join(File.dirname(__FILE__), 'states', '*.rb')].each do |file|
      require file
    end
    
    def self.process(state, bot, message, session)
      state_class = state.capitalize
      
      unless const_defined?(state_class)
        state_class = state.split('_').map(&:capitalize).join('_')
      end
      
      if const_defined?(state_class)
        const_get(state_class).new(bot, message, session).process
      else
        bot.api.send_message(
          chat_id: message.chat.id,
          text: I18n.t('unknown_command')
        )
      end
    end
  end
end