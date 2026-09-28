class SalaryImportError < ApplicationRecord
  belongs_to :salary_import

  belongs_to :employee, optional: true

  validates :row_number, presence: true
  validates :error_message, presence: true

  validate :raw_data_presence

  private

  def raw_data_presence
    errors.add(:raw_data, :blank) if raw_data.nil?
  end
end
