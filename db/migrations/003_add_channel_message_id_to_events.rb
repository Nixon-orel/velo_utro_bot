class AddChannelMessageIdToEvents < ActiveRecord::Migration[7.0]
  def change
    add_column :events, :channel_message_id, :integer
  end
end