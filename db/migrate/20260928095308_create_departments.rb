class CreateDepartments < ActiveRecord::Migration[8.1]
  def change
    # LLD §2.4 — reference data an employee belongs to. The name is unique
    # because the directory filter and the department reports group by it.
    create_table :departments do |t|
      t.string :name, null: false

      t.timestamps
    end

    add_index :departments, :name, unique: true
  end
end
