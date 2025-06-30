require_relative 'edit_handler'

module Bot
  module States
    class Edit_time < EditHandler
      def process
        time_pattern = /^\d{1,2}:\d{2}(-\d{1,2}:\d{2})?$/
        edit_event_field(:time, @message.text, 'time_changed', 'time_saved', time_pattern)
      end
    end
  end
end