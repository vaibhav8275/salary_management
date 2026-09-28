class CreateSalaryImports < ActiveRecord::Migration[8.1]
  def change
    create_table :salary_imports do |t|
      t.string :filename, null: false
      t.string :s3_object_key, null: false
      t.integer :status, null: false, default: 0
      t.integer :total_records, null: false
      t.integer :processed_records, null: false
      t.integer :failed_records, null: false
      t.bigint :created_by, null: false
      t.datetime :started_at

      t.timestamps
    end
  end
end
