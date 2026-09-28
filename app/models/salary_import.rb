class SalaryImport < ApplicationRecord
  # LLD §8.2 — status is persisted as a Rails enum backed by an integer column.
  # The stored values are part of the schema; do not renumber them.
  enum :status, {
    pending: 0,
    processing: 1,
    completed: 2,
    completed_with_errors: 3,
    failed: 4
  }

  has_many :salary_import_errors, dependent: :destroy
end
