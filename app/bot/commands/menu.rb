require_relative '../handlers/info_command_handler'

module Bot
  module Commands
    class Menu < Bot::Handlers::InfoCommandHandler
      private
      
      def message_key
        'menu'
      end
    end
  end
end