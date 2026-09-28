class CreateSalaryImportErrors < ActiveRecord::Migration[8.1]
  def change
    create_table :salary_import_errors do |t|
      t.references :salary_import, null: false, foreign_key: true
      t.integer :row_number, null: false
      t.references :employee, null: true, foreign_key: true
      t.text :error_message, null: false
      t.jsonb :raw_data, null: false

      t.datetime :created_at, null: false
    end
  end
end
