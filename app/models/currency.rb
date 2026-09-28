class Currency < ApplicationRecord
  validates :code, :name, :symbol, presence: true
  validates :code, uniqueness: true, length: { is: 3 }

  has_many :countries, dependent: :restrict_with_error
end
