require_relative '../handlers/info_command_handler'

module Bot
  module Commands
    class Help < Bot::Handlers::InfoCommandHandler
      private
      
      def message_key
        'help'
      end
    end
  end
end