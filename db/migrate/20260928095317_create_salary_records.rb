class CreateSalaryRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :salary_records do |t|
      t.references :employee, null: false, foreign_key: true
      t.decimal :base_salary, precision: 15, scale: 2, null: false
      t.decimal :bonus, precision: 15, scale: 2, null: false
      t.decimal :allowance, precision: 15, scale: 2, null: false
      t.date :effective_date, null: false

      t.timestamps

      t.index :effective_date
      t.index %i[employee_id effective_date], unique: true

      t.check_constraint "base_salary >= 0", name: "salary_records_base_salary_non_negative"
      t.check_constraint "bonus >= 0", name: "salary_records_bonus_non_negative"
      t.check_constraint "allowance >= 0", name: "salary_records_allowance_non_negative"
    end
  end
end
