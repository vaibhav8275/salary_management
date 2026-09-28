# Reference data required for the application to run in every environment.
# Idempotent: safe to run repeatedly (`bin/rails db:seed`).
#
# Three small tables feed the whole application: `currencies` (LLD §2.2),
# departments (LLD §2.4) and countries (LLD §2.3). They are read on nearly
# every request and written almost never, so they are also the tables cached
# permanently in Redis (ARCHITECTURE.md §7.2) — seeding them is what fills that
# cache for a fresh environment.
#
# Currencies — `code` is an ISO 4217 code, unique and limited to 3 characters;
# `name` and `symbol` are required. The four below are the currencies the
# documented scenarios use (LLD §2.2 and the multi-currency reporting example in
# §11); the rest are the common additions a developer needs for local work.

CURRENCIES = [
  { code: "USD", name: "US Dollar",        symbol: "$"  },
  { code: "EUR", name: "Euro",             symbol: "€"  },
  { code: "GBP", name: "British Pound",    symbol: "£"  },
  { code: "INR", name: "Indian Rupee",     symbol: "₹"  },
  { code: "CAD", name: "Canadian Dollar",  symbol: "$"  },
  { code: "AUD", name: "Australian Dollar", symbol: "$"  },
  { code: "JPY", name: "Japanese Yen",     symbol: "¥"  },
  { code: "CHF", name: "Swiss Franc",      symbol: "₣"  }
].freeze

CURRENCIES.each do |attributes|
  Currency.find_or_create_by!(code: attributes[:code]) do |currency|
    currency.name = attributes[:name]
    currency.symbol = attributes[:symbol]
  end
end

puts "Seeded #{Currency.count} currencies."

# Departments — the name is unique because the directory filter and the
# "total payroll by department" report group by it (LLD §2.4, §11).

DEPARTMENTS = [
  "Engineering",
  "Sales",
  "Finance",
  "Human Resources",
  "Operations",
  "Marketing",
  "Customer Support",
  "Product"
].freeze

DEPARTMENTS.each do |name|
  Department.find_or_create_by!(name: name)
end

puts "Seeded #{Department.count} departments."

# Countries — a country is paid in the currency of the country it names, so the
# currency is a foreign key rather than a second attribute to keep in step
# (BR-8, LLD §2.8). A handful of realistic rows is enough for local work and for
# the multi-currency reporting example; only currencies seeded above are used.

COUNTRIES = [
  { name: "United States",  currency_code: "USD" },
  { name: "United Kingdom", currency_code: "GBP" },
  { name: "India",          currency_code: "INR" },
  { name: "Germany",        currency_code: "EUR" },
  { name: "France",         currency_code: "EUR" },
  { name: "Canada",         currency_code: "CAD" },
  { name: "Australia",      currency_code: "AUD" },
  { name: "Japan",          currency_code: "JPY" },
  { name: "Switzerland",    currency_code: "CHF" }
].freeze

COUNTRIES.each do |attributes|
  Country.find_or_create_by!(name: attributes[:name]) do |country|
    country.currency = Currency.find_by!(code: attributes[:currency_code])
  end
end

puts "Seeded #{Country.count} countries."
