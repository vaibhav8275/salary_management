#!/usr/bin/env ruby
# Generate sample salary bulk import CSV with 10,000 records
# Columns: employee_id, effective_date, base_salary, bonus, allowance, country_id, department_id, job_title_id

require 'csv'
require 'faker'
require 'date'

# Ensure we have the faker gem; if not, we can use simple arrays
# But we can also use built-in randomization.

# Load reference data counts from seeds (approximate)
DEPARTMENT_COUNT = 8   # Engineering, Sales, Finance, Human Resources, Operations, Marketing, Customer Support, Product
COUNTRY_COUNT = 9      # US, UK, India, Germany, France, Canada, Australia, Japan, Switzerland
JOB_TITLE_COUNT = 10   # Software Engineer, Senior Software Engineer, Lead Software Engineer, Engineering Manager, Director of Engineering, VP of Engineering, Product Manager, Sales Representative, HR Specialist, Finance Analyst

# We'll generate 10,000 employees first, assigning them random reference IDs
# Then for each employee, generate one salary import record.

employees = []
(1..10000).each do |i|
  employees << {
    id: i,
    department_id: rand(1..DEPARTMENT_COUNT),
    country_id: rand(1..COUNTRY_COUNT),
    job_title_id: rand(1..JOB_TITLE_COUNT)
  }
end

# Salary ranges (in USD for simplicity; in real system would be in employee's currency)
BASE_SALARY_RANGE = 30000..200000
BONUS_RANGE = 0..50000
ALLOWANCE_RANGE = 0..20000

# Effective date range: past 2 years to future 1 year (but import will filter future dates?)
START_DATE = Date.today - 2.years
END_DATE = Date.today + 1.year

CSV.open("salary_import_sample.csv", "w") do |csv|
  # Write header
  csv << [ "employee_id", "effective_date", "base_salary", "bonus", "allowance", "country_id", "department_id", "job_title_id" ]

  employees.each do |emp|
    effective_date = rand(START_DATE..END_DATE)
    base_salary = rand(BASE_SALARY_RANGE)
    bonus = rand(BONUS_RANGE)
    allowance = rand(ALLOWANCE_RANGE)

    csv << [
      emp[:id],
      effective_date.strftime("%Y-%m-%d"),
      base_salary,
      bonus,
      allowance,
      emp[:country_id],
      emp[:department_id],
      emp[:job_title_id]
    ]
  end
end

puts "Generated salary_import_sample.csv with #{employees.length} records."
