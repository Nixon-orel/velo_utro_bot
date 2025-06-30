class CreateTables < ActiveRecord::Migration[8.0]
  def change
    create_table :users do |t|
      t.string :nickname
      t.string :username, null: false
      t.string :telegram_id, null: false
      t.timestamps
    end
    
    add_index :users, :telegram_id, unique: true
    
    create_table :events do |t|
      t.date :date, null: false
      t.string :time, null: false
      t.string :event_type, null: false
      t.string :location, null: false
      t.string :distance
      t.string :pace
      t.text :additional_info
      t.references :author, null: false, foreign_key: { to_table: :users }
      t.timestamps
    end
    
    create_table :participants do |t|
      t.references :event, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.timestamps
    end
    
    add_index :participants, [:event_id, :user_id], unique: true
    
    create_table :sessions do |t|
      t.string :user_id, null: false
      t.text :data
      t.timestamps
    end
    
    add_index :sessions, :user_id, unique: true
  end
end