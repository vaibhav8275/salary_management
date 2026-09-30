# Reference data required for the application to run in every environment.
# Idempotent: safe to run repeatedly (`bin/rails db:seed`).
#
# The employee block further down is synthetic and only ever appropriate for
# local and test work, so that block refuses to run outside those environments.
# The reference data above it is real, and a deployment may legitimately want it.
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

# Job titles — standardized roles an employee belongs to (LLD §2.9). Titles are
# stored exactly as written below: the model trims and squeezes spaces before
# saving and refuses a case variant, so seeding one canonical spelling keeps
# every employee in the same role row.

JOB_TITLES = [
  "Software Engineer",
  "Senior Software Engineer",
  "Lead Software Engineer",
  "Engineering Manager",
  "Director of Engineering",
  "VP of Engineering",
  "Product Manager",
  "Sales Representative",
  "HR Specialist",
  "Finance Analyst"
].freeze

JOB_TITLES.each do |title|
  JobTitle.find_or_create_by!(title: title)
end

puts "Seeded #{JobTitle.count} job titles."

# Employees — synthetic rows for local development and for exercising the
# ~10,000-employee dataset the directory and reports are specified against
# (FR-1.7). Faker generates the name and email; the four foreign keys are drawn
# from the reference tables seeded above, so every row resolves to a real
# department, country and job title.
#
# Guarded to non-production environments. These are fabricated people: seeding
# them into a real database would corrupt salary reports and the audit trail,
# and nothing should be able to do that by running one task.
#
# The email is unique byte-for-byte (app/models/employee.rb mirrors the unique
# index) and is made unique by construction from a sequence number, so the loop
# stops only on a genuine failure rather than skipping colliding rows. Set
# EMPLOYEE_COUNT to seed a different volume; the default matches the dataset
# size in the documentation.
#
# These are fabricated names on reserved .test domains (RFC 6761), so no
# synthetic row can reach a real inbox. Re-running only fills the table up to
# the requested count and never duplicates or deletes existing rows.

EMPLOYEE_COUNT = Integer(ENV.fetch("EMPLOYEE_COUNT", 10_000))

if Rails.env.production?
  abort "Refusing to seed synthetic employees in production. " \
        "Run this only in development or test."
end

def build_employee_attributes(departments, countries, job_titles, sequence)
  {
    first_name: Faker::Name.first_name,
    last_name: Faker::Name.last_name,
    # The sequence number is appended because name-derived local parts collide
    # surprisingly often at this volume — a plain Faker unique-email run skipped
    # ~3% of 10,000 rows. `Faker::Internet.username` yields the local part only,
    # so the sequence is appended to it and the reserved .test domain is added
    # once, keeping the address both unique by construction and undeliverable.
    email: "#{Faker::Internet.username}-#{sequence}@example.test",
    hire_date: Faker::Date.backward(days: Faker::Number.between(from: 90, to: 365 * 12)),
    department: departments.sample,
    country: countries.sample,
    job_title: job_titles.sample
  }
end

# Reference rows are looked up once and passed in, because `.sample` inside the
# per-employee loop would re-query on every iteration — 10,000 employees would
# issue 30,000 pointless SELECTs.
department_records = Department.order(:id).to_a
country_records = Country.order(:id).to_a
job_title_records = JobTitle.order(:id).to_a

if department_records.empty? || country_records.empty? || job_title_records.empty?
  puts "Skipping employees: seed the reference tables above first."
  return
end

existing = Employee.count
if existing >= EMPLOYEE_COUNT
  puts "Employees already seeded (#{existing})."
  return
end

created = 0
collisions = 0

(EMPLOYEE_COUNT - existing).times do |index|
  # Offset the sequence by what is already in the table, so a second run that
  # tops the table up does not reissue addresses the first run already used.
  attributes = build_employee_attributes(
    department_records, country_records, job_title_records, existing + index + 1
  )
  employee = Employee.create(attributes)

  if employee.persisted?
    created += 1
  else
    collisions += 1
    # Only a duplicate email is tolerable here; anything else is a real seed bug.
    unless employee.errors.of_kind?(:email, :taken)
      warn "Seeding stopped: #{employee.errors.full_messages.to_sentence}"
      break
    end
  end
end

puts "Seeded #{created} employees (#{Employee.count} total#{collisions.positive? ? ", #{collisions} email collisions skipped" : ''})."
