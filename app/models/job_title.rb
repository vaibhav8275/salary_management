class JobTitle < ApplicationRecord
  has_many :employees, dependent: :restrict_with_error

  validates :title, presence: true, uniqueness: { case_sensitive: false }

  before_validation :normalize_title

  private

  def normalize_title
    return if title.nil?

    self.title = title.strip.squeeze(" ")
  end
end
