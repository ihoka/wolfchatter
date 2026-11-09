class CreateChatrooms < ActiveRecord::Migration[8.1]
  def change
    create_table :chatrooms do |t|
      t.decimal :latitude, precision: 10, scale: 6, null: false
      t.decimal :longitude, precision: 10, scale: 6, null: false
      t.string :place_name

      t.timestamps
    end
  end
end
