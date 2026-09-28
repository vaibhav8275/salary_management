class CreateEmployees < ActiveRecord::Migration[8.1]
  def change
    create_table :employees do |t|
      t.string :first_name, null: false
      t.string :last_name, null: false
      t.string :email, null: false
      t.string :department, null: false
      t.string :country, null: false
      t.date :hire_date, null: false
      t.references :currency, null: false, foreign_key: true

      t.timestamps

      t.index :email, unique: true
      t.index :department
      t.index :country
      t.index :first_name
      t.index :last_name
    end
  end
end
