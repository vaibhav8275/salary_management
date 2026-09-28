require "bigdecimal"

class ReportService
  BANDS = [
    [ 0, 25_000, "0-25000" ],
    [ 25_000, 50_000, "25000-50000" ],
    [ 50_000, 75_000, "50000-75000" ],
    [ 75_000, 100_000, "75000-100000" ],
    [ 100_000, nil, "100000+" ]
  ].freeze

  def average_salary_by_department(department: nil, country: nil, from: nil, to: nil)
    scope = SalaryRecord
      .joins(employee: [ :department, { country: :currency } ])
      .group("departments.name", "currencies.code")
      .order("departments.name ASC, currencies.code ASC")
      .select(
        "departments.name AS department",
        "currencies.code AS currency",
        "AVG(salary_records.base_salary) AS amount"
      )

    scope = apply_filters(scope, department: department, country: country, from: from, to: to)

    scope.map do |row|
      { department: row.department, currency: row.currency, amount: to_decimal(row.amount) }
    end
  end

  def total_payroll_by_country(department: nil, country: nil, from: nil, to: nil)
    scope = SalaryRecord
      .joins(employee: { country: :currency, department: {} })
      .group("countries.name", "currencies.code")
      .order("countries.name ASC")
      .select(
        "countries.name AS country",
        "currencies.code AS currency",
        "SUM(salary_records.base_salary + salary_records.bonus + salary_records.allowance) AS amount"
      )

    scope = apply_filters(scope, department: department, country: country, from: from, to: to)

    scope.map do |row|
      { country: row.country, currency: row.currency, amount: to_decimal(row.amount) }
    end
  end

  def employee_count_by_department(department: nil, country: nil)
    scope = Employee
      .joins(:department, :country)
      .group("departments.name")
      .order("departments.name ASC")
      .select("departments.name AS department_name, COUNT(employees.id) AS count")

    scope = apply_employee_filters(scope, department: department, country: country)

    scope.map { |row| { department: row.department_name, count: row.count } }
  end

  def employee_count_by_country(department: nil, country: nil)
    scope = Employee
      .joins(:country, :department)
      .group("countries.name")
      .order("countries.name ASC")
      .select("countries.name AS country_name, COUNT(employees.id) AS count")

    scope = apply_employee_filters(scope, department: department, country: country)

    scope.map { |row| { country: row.country_name, count: row.count } }
  end

  def salary_distribution(department: nil, country: nil, from: nil, to: nil)
    scope = SalaryRecord.joins(employee: [ :department, { country: :currency } ])
    scope = apply_filters(scope, department: department, country: country, from: from, to: to)

    counts = Hash.new(0)
    scope.pluck("currencies.code", "salary_records.base_salary").each do |currency, salary|
      counts[[ currency, band_for(salary) ]] += 1
    end

    counts.map do |(currency, range), count|
      { range: range, count: count, currency: currency }
    end.sort_by { |row| [ band_index(row[:range]), row[:currency] ] }
  end

  def salary_trends(department: nil, country: nil, from: nil, to: nil)
    scope = SalaryRecord
      .joins(employee: [ :department, { country: :currency } ])
      .group("salary_records.effective_date", "currencies.code")
      .order("salary_records.effective_date ASC, currencies.code ASC")
      .select(
        "salary_records.effective_date",
        "currencies.code AS currency",
        "AVG(salary_records.base_salary) AS amount"
      )

    scope = apply_filters(scope, department: department, country: country, from: from, to: to)

    scope.map do |row|
      { effective_date: row.effective_date, currency: row.currency, amount: to_decimal(row.amount) }
    end
  end

  private

  def apply_filters(scope, department: nil, country: nil, from: nil, to: nil)
    scope = scope.where(departments: { name: department }) if department.present?
    scope = scope.where(countries: { name: country }) if country.present?
    scope = scope.where("salary_records.effective_date >= ?", from) if from.present?
    scope = scope.where("salary_records.effective_date <= ?", to) if to.present?
    scope
  end

  def apply_employee_filters(scope, department: nil, country: nil)
    scope = scope.where(departments: { name: department }) if department.present?
    scope = scope.where(countries: { name: country }) if country.present?
    scope
  end

  def band_for(salary)
    BANDS.find { |lower, upper, _label| salary >= lower && (upper.nil? || salary < upper) }.last
  end

  def band_index(range)
    BANDS.index { |_lower, _upper, label| label == range } || 0
  end

  def to_decimal(value)
    value.is_a?(BigDecimal) ? value : BigDecimal(value.to_s)
  rescue ArgumentError
    BigDecimal("0")
  end
end
