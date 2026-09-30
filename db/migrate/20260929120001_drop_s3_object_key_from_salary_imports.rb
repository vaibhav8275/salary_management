# The uploaded CSV is an Active Storage attachment now (`has_one_attached
# :csv_file`, LLD §2.6), so the import row no longer stores a key it has to keep
# in step with a file somewhere else. Two sources of truth for one object is how
# an import ends up pointing at a key that was never uploaded.
class DropS3ObjectKeyFromSalaryImports < ActiveRecord::Migration[8.1]
  def change
    remove_column :salary_imports, :s3_object_key, :string, null: false
  end
end
