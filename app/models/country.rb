class Country < ApplicationRecord
  belongs_to :currency

  validates :name, presence: true, uniqueness: true

  has_many :employees, dependent: :restrict_with_error
end
