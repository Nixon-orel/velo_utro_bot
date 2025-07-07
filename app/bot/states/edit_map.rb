require_relative 'edit_handler'

module Bot
  module States
    class EditMap < EditHandler
      def process
        edit_event_field(:map, @message.text, 'map_changed', 'map_saved')
      end
    end
  end
end