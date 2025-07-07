require_relative 'base_handler'
require_relative 'command_handler'

module Bot
  module Commands
    Dir[File.join(File.dirname(__FILE__), 'commands', '*.rb')].each do |file|
      require file
    end
    
    def self.execute(command, bot, message, session)
      command_class = command.split('_').map(&:capitalize).join('')
      
      if const_defined?(command_class)
        const_get(command_class).new(bot, message, session).execute
      else
        bot.api.send_message(
          chat_id: message.chat.id,
          text: I18n.t('unknown_command')
        )
      end
    end
  end
end