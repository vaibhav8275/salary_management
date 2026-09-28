class Employee < ApplicationRecord
  # LLD §2.1 — an employee is placed in a department and a country, both of which
  # are foreign keys into reference tables rather than free-text columns, so a
  # misspelled department cannot enter the data and the directory filters and
  # reports group by an indexed id.
  belongs_to :department
  belongs_to :country

  # BR-8, LLD §2.8 — the employee's salary currency is not stored on the
  # employee; it is the currency of the country the employee belongs to. This
  # association is the readable form of that path, so `employee.currency` and
  # `employee.country.currency` are the same currency by construction and cannot
  # drift apart.
  has_one :currency, through: :country
end
