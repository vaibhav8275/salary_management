class CreateCountries < ActiveRecord::Migration[8.1]
  def change
    # LLD §2.3 — reference data an employee belongs to, and the reason their
    # salary has a currency: a country is paid in exactly one currency, so the
    # employee's currency is reached through their country rather than stored on
    # the employee. The name is unique because the directory filter and the
    # country reports group by it.
    create_table :countries do |t|
      t.string :name, null: false
      t.bigint :currency_id, null: false

      t.timestamps
    end

    add_index :countries, :name, unique: true
    add_index :countries, :currency_id
    add_foreign_key :countries, :currencies
  end
end
