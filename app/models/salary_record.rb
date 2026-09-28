class SalaryRecord < ApplicationRecord
  belongs_to :employee

  has_paper_trail

  validates :employee, presence: true
  validates :effective_date, presence: true
  validates :base_salary, :bonus, :allowance,
    numericality: { greater_than_or_equal_to: 0 }

  validates :effective_date, uniqueness: { scope: :employee_id }
end
