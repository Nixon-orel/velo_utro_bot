require_relative 'edit_handler'

module Bot
  module States
    class EditTime < EditHandler
      def process
        time_pattern = EventTime::INPUT_FORMAT
        edit_event_field(:time, @message.text.strip, 'time_changed', 'time_saved', time_pattern)
      end
    end
  end
end
