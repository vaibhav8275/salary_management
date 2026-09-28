# `currencies` is reference data (LLD §2.2): the valid currency values, their
# display names and their symbols. Countries reference a currency (LLD §2.3) —
# an employee reaches their salary currency through their country — so a
# currency is never referenced directly by an employee, and the table is one of
# the three cached permanently in Redis (ARCHITECTURE.md §7.2).
class Currency < ApplicationRecord
  # A currency in use by a country is not removed: it is the reason every
  # employee in that country has a currency at all, and a country has no
  # currency-less form to fall back to (`countries.currency_id` is NOT NULL,
  # LLD §2.3, §3).
  has_many :countries, dependent: :restrict_with_error
end
