class CreateCurrencies < ActiveRecord::Migration[8.1]
  def change
    create_table :currencies do |t|
      t.string :code, limit: 3, null: false
      t.string :name, null: false
      t.string :symbol, null: false

      t.timestamps

      t.index :code, unique: true
    end
  end
end
