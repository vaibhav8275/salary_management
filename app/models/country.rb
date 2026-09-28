# A `country` is reference data (LLD §2.3) and it is what makes an employee's
# salary currency unambiguous: the country owns the currency, so the currency is
# reached as `employee.country.currency` rather than from a column on the
# employee (BR-8, LLD §2.8).
#
# The rows are small and change rarely, which is why they are read from the
# permanent Redis cache rather than joined per row (ARCHITECTURE.md §7.2).
class Country < ApplicationRecord
  belongs_to :currency

  has_many :employees, dependent: :restrict_with_error
end
