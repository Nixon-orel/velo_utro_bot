require_relative 'participation_handler'

module Bot
  module Callbacks
    class Join < ParticipationHandler
      def process
        handle_participation(true)
      end
    end
  end
end