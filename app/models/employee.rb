class Employee < ApplicationRecord
  belongs_to :department
  belongs_to :country
  belongs_to :job_title

  has_one :currency, through: :country

  has_many :salary_records

  validates :first_name, :last_name, :email, :hire_date, presence: true
  validates :department, :country, :job_title, presence: true

  validates :email, uniqueness: true
end
