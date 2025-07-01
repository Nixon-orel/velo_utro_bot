module Bot
  module Callbacks
    class Edit < Bot::CallbackHandler
      def process
        event = get_event
        return unless event
        
        unless event.author_id == @user.id
          answer_callback_query(I18n.t('not_author'), show_alert: true)
          return
        end
        
        buttons = [
          [
            create_button(
              I18n.t('buttons.edit_date'),
              "edit_date-#{event.id}"
            )
          ],
          [
            create_button(
              I18n.t('buttons.edit_time'),
              "edit_time-#{event.id}"
            )
          ],
          [
            create_button(
              I18n.t('buttons.edit_place'),
              "edit_location-#{event.id}"
            )
          ]
        ]
        
        unless event.static?
          buttons << [
            create_button(
              I18n.t('buttons.edit_track'),
              "edit_track-#{event.id}"
            )
          ]
          buttons << [
            create_button(
              I18n.t('buttons.edit_map'),
              "edit_map-#{event.id}"
            )
          ]
        end
        
        buttons << [
          create_button(
            I18n.t('buttons.edit_info'),
            "edit_info-#{event.id}"
          )
        ]
        
        markup = create_keyboard(buttons)
        
        send_html_message(I18n.t('edit_message'), { reply_markup: markup })
        
        answer_callback_query()
      end
    end
  end
end
