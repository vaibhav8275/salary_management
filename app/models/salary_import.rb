class SalaryImport < ApplicationRecord
  enum :status, {
    pending: 0,
    processing: 1,
    completed: 2,
    completed_with_errors: 3,
    failed: 4
  }

  has_many :salary_import_errors, dependent: :destroy
end
