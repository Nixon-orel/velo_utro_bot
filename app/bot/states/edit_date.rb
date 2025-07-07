require_relative 'edit_handler'

module Bot
  module States
    class EditDate < EditHandler
      def process
        send_message(I18n.t('invalid_input'))
      end
    end
  end
end