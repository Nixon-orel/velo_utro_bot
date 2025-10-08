require_relative '../handlers/info_command_handler'

module Bot
  module Commands
    class Start < Bot::Handlers::InfoCommandHandler
      private
      
      def message_key
        'start'
      end
    end
  end
end