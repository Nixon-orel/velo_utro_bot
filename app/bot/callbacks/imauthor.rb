module Bot
  module Callbacks
    class Imauthor < Bot::CallbackHandler
      def process
        return unless ensure_private_chat

        answer_callback_query
        events = Event.upcoming_for_author(@user)

        delete_message
        return send_message(I18n.t('no_events')) if events.empty?

        events.each do |event|
          buttons = [
            [create_button(I18n.t('buttons.edit'), "edit-#{event.id}")],
            [create_button(I18n.t('buttons.delete'), "delete-#{event.id}")]
          ]
          unless event.published?
            buttons << [create_button(I18n.t('buttons.publish'), "publish-#{event.id}")]
          end

          send_html_message(
            Bot::Helpers::Formatter.event_info(event),
            reply_markup: create_keyboard(buttons)
          )
        end
      end
    end
  end
end
