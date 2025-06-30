require_relative 'edit_handler'

module Bot
  module States
    class Edit_info < EditHandler
      def process
        edit_event_field(:additional_info, @message.text, 'info_changed', 'info_saved')
      end
    end
  end
end