class AddLocationIndexToChatrooms < ActiveRecord::Migration[8.1]
  def change
    add_index :chatrooms, [ :latitude, :longitude ]
  end
end
