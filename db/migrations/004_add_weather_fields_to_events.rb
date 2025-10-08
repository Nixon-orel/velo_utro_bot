class AddWeatherFieldsToEvents < ActiveRecord::Migration[7.0]
  def change
    add_column :events, :weather_data, :jsonb
    add_column :events, :weather_history, :jsonb, default: []
    add_column :events, :weather_updated_at, :datetime
    add_column :events, :weather_alerts_sent, :jsonb, default: {}
    add_column :events, :weather_city, :string
    add_column :events, :latitude, :decimal, precision: 10, scale: 6
    add_column :events, :longitude, :decimal, precision: 10, scale: 6
  end
end