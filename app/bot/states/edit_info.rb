require_relative 'edit_handler'

module Bot
  module States
    class EditInfo < EditHandler
      def process
        edit_event_field(:additional_info, @message.text, 'info_changed', 'info_saved')
      end
    end
  end
end