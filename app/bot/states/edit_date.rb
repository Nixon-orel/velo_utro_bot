require_relative 'edit_handler'

module Bot
  module States
    class EditDate < EditHandler
      def process
        if @message.text.start_with?('calendar_')
          selected_date = @message.text.split('_')[1]
          
          begin
            new_date = Date.parse(selected_date)
            edit_event_field(:date, new_date, 'date_changed', 'date_saved')
          rescue ArgumentError
            send_message(I18n.t('invalid_input'))
          end
        else
          send_message(I18n.t('invalid_input'))
        end
      end
    end
  end
end