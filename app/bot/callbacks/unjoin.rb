require_relative 'participation_handler'

module Bot
  module Callbacks
    class Unjoin < ParticipationHandler
      def process
        handle_participation(false)
      end
    end
  end
end