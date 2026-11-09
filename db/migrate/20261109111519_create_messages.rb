class CreateMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :messages do |t|
      t.references :chatroom, null: false, foreign_key: true, index: false
      t.string :author_name, null: false
      t.text :body, null: false

      t.timestamps
    end

    add_index :messages, %i[chatroom_id created_at]
  end
end
