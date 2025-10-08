require 'active_record'

class AddPublishedToEvents < ActiveRecord::Migration[6.1]
  def up
    add_column :events, :published, :boolean, default: false, null: false
    execute "UPDATE events SET published = true"
  end

  def down
    remove_column :events, :published
  end
end