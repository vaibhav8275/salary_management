class AddCreatedByForeignKeyToSalaryImports < ActiveRecord::Migration[8.1]
  def change
    add_foreign_key :salary_imports, :users, column: :created_by
  end
end
