# `departments` is reference data (LLD §2.4): a small, slowly changing table
# that employees belong to. The rows are what the directory filter and the
# "total payroll by department" report group by, so the name is unique and the
# table is one of the three cached permanently in Redis (ARCHITECTURE.md §7.2).
class Department < ApplicationRecord
  has_many :employees, dependent: :restrict_with_error
end
