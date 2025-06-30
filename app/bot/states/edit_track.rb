require_relative 'edit_handler'

module Bot
  module States
    class Edit_track < EditHandler
      def process
        edit_event_field(:track, @message.text, 'track_changed', 'track_saved')
      end
    end
  end
end