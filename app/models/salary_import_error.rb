class SalaryImportError < ApplicationRecord
  belongs_to :salary_import
  belongs_to :employee
end
