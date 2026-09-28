# Reference data required for the application to run in every environment.
# Idempotent: safe to run repeatedly (`bin/rails db:seed`).
#
# Currencies (LLD §2.2) — `code` is an ISO 4217 code, unique and limited to 3
# characters; `name` and `symbol` are required. The four below are the currencies
# the documented scenarios use (LLD §2.2 and the multi-currency reporting example
# in §11); the rest are the common additions a developer needs for local work.

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
