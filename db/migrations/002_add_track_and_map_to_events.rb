class AddTrackAndMapToEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :events, :track, :string
    add_column :events, :map, :string
  end
end