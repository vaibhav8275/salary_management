class Department < ApplicationRecord
  validates :name, presence: true, uniqueness: true

  has_many :employees, dependent: :restrict_with_error
end
