class AddPublishedAtToEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :events, :published_at, :datetime
  end
end
