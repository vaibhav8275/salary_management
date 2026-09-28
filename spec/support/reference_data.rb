# Reference data shared inside one example or scenario.
#
# `currencies.code`, `countries.name` and `departments.name` each carry a unique
# index (LLD §2.2, §2.3, §2.4), so a second `create` for the same value would
# fail rather than hand out a private row. Report examples group by currency,
# department and country, which also means the value has to be the expected ISO
# code or documented name and not a generated one.
#
# FactoryBot creates one row per call, so the values are looked up first and only
# created once. The row is visible to the rest of the example because examples run
# inside a transaction, so a later `find_by` sees the uncommitted row and never
# asks for a second one.
#
# `db/seeds.rb` is not loaded into the test database, so the names and symbols are
# the same values the seeds use.
#
# Performance / deadlock note
# ---------------------------
# `find_or_create_by!` is not atomic: it does SELECT then INSERT as two
# separate statements. When a test creates many employees in a loop (e.g. the
# FR-1.7 scale example that builds 10,000 rows), every iteration calls
# `ReferenceData.department("Engineering")` and hits the same unique-index
# entry. Under concurrent or rapid sequential lock pressure PostgreSQL can
# detect a deadlock and abort one of the transactions.
#
# The fix is an in-process, per-test cache keyed by (model, identifier).
# Within one example the first call goes to the database and every subsequent
# call returns the already-resolved AR object instantly, so `find_or_create_by!`
# is called at most once per name per example instead of N times.
#
# `reset!` is called in the `before` hook (rails_helper.rb / hooks.rb) so that
# the cache does not bleed across examples.  The database rows are rolled back by
# transactional fixtures; the Ruby-side cache just needs to be cleared to match.
module ReferenceData
  CURRENCIES = {
    "USD" => [ "US Dollar", "$" ],
    "EUR" => [ "Euro", "€" ],
    "GBP" => [ "British Pound", "£" ],
    "INR" => [ "Indian Rupee", "₹" ],
    "CAD" => [ "Canadian Dollar", "$" ],
    "AUD" => [ "Australian Dollar", "$" ],
    "JPY" => [ "Japanese Yen", "¥" ],
    "CHF" => [ "Swiss Franc", "₣" ]
  }.freeze

  # The currency a country is paid in, for the countries the documented scenarios
  # use. Same values as `db/seeds.rb`, so "United Kingdom" in a report means
  # pounds rather than whatever the default happened to be. A country that is not
  # listed is created in the default currency, which is the USD the
  # multi-currency examples vary away from.
  COUNTRY_CURRENCIES = {
    "United States" => "USD",
    "United Kingdom" => "GBP",
    "India" => "INR",
    "Germany" => "EUR",
    "France" => "EUR",
    "Canada" => "CAD",
    "Australia" => "AUD",
    "Japan" => "JPY",
    "Switzerland" => "CHF"
  }.freeze

  DEFAULT_CURRENCY = "USD"

  # Clears the in-process cache.  Call this in the before hook for every
  # example / scenario so rows from a previous (rolled-back) transaction are
  # not returned after the next transaction begins.
  def self.reset!
    @cache = {}
  end

  def self.cache
    @cache ||= {}
  end

  def self.currency(code)
    cache[[ :currency, code ]] ||= Currency.find_or_create_by!(code: code) do |currency|
      currency.name, currency.symbol = CURRENCIES.fetch(code) { [ "Test Currency #{code}", code ] }
    end
  end

  # A country keeps the currency it was first created with (LLD §2.3, §2.8): the
  # country owns the currency, so asking for the same country in two currencies
  # returns the first one rather than quietly changing the salaries of every
  # employee already in that country. Pass a code to override the documented one.
  def self.country(name, currency_code = nil)
    cache[[ :country, name ]] ||= Country.find_or_create_by!(name: name) do |country|
      country.currency = currency(currency_code || COUNTRY_CURRENCIES.fetch(name, DEFAULT_CURRENCY))
    end
  end

  def self.department(name)
    cache[[ :department, name ]] ||= Department.find_or_create_by!(name: name)
  end

  # A title is unique case-insensitively (LLD §2.9), so the canonical spelling
  # is looked up before a row is created.
  def self.job_title(title)
    cache[[ :job_title, title ]] ||= JobTitle.find_or_create_by!(title: title)
  end

  # A country that is paid in the given currency, for the steps that state a
  # currency rather than a country ("an employee exists with currency GBP"). A
  # currency with no documented country gets a name of its own so it cannot
  # collide with a real one.
  def self.country_paid_in(currency_code)
    name = COUNTRY_CURRENCIES.key(currency_code) || "Country paid in #{currency_code}"

    country(name, currency_code)
  end
end
