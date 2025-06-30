require_relative 'edit_handler'

module Bot
  module States
    class Edit_location < EditHandler
      def process
        edit_event_field(:location, @message.text, 'location_changed', 'location_saved')
      end
    end
  end
end