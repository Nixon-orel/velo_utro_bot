class AddSubscribedToNotificationsToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :subscribed_to_notifications, :boolean, default: false, null: false
  end
end
