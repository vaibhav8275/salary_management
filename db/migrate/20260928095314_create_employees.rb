class CreateEmployees < ActiveRecord::Migration[8.1]
  def change
    # LLD §2.1 — an employee is placed in a department and a country rather than
    # carrying those names as free text, and has no currency column: the currency
    # is the one their country is paid in (BR-8, LLD §2.3).
    create_table :employees do |t|
      t.string :first_name, null: false
      t.string :last_name, null: false
      t.string :email, null: false
      t.references :department, null: false, foreign_key: true, index: true
      t.references :country, null: false, foreign_key: true, index: true
      t.date :hire_date, null: false

      t.timestamps

      t.index :email, unique: true
      t.index :first_name
      t.index :last_name
    end
  end
end
