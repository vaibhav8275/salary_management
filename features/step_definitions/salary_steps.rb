# Salary management and salary history steps
# (REQUIREMENTS FR-2.1 – FR-2.4, FR-2.6, BR-1, BR-2; LLD §5.1 – §5.3).
#
# The LLD leaves request payload shape open, so create and update send the
# attributes at the top level, which is the plainest JSON body for a Rails API.
Given(/^the employee "([^"]*)" has a salary of ([0-9.]+)(?: ([A-Z]{3}))? effective from (\d{4}-\d{2}-\d{2})$/) do |name, amount, _code, date|
  create(:salary_record,
    employee: employee_named(name),
    base_salary: decimal_amount(amount),
    bonus: 0,
    allowance: 0,
    effective_date: parse_date(date)
  )
end

Given(/^the employee "([^"]*)" has a future dated salary of ([0-9.]+)(?: ([A-Z]{3}))? effective from (\d{4}-\d{2}-\d{2})$/) do |name, amount, _code, date|
  effective_date = parse_date(date)
  raise "Test setup error: #{date} is not in the future" unless effective_date > Date.current

  create(:salary_record,
    employee: employee_named(name),
    base_salary: decimal_amount(amount),
    bonus: 0,
    allowance: 0,
    effective_date: effective_date
  )
end

Given('the employee {string} has salary history:') do |name, table|
  table.hashes.each do |row|
    create(:salary_record,
      employee: employee_named(name),
      base_salary: decimal_amount(row["base_salary"]),
      bonus: decimal_amount(row["bonus"]),
      allowance: decimal_amount(row["allowance"]),
      effective_date: parse_date(row["effective_date"])
    )
  end
end

Given("the following current salaries exist:") do |table|
  table.hashes.each do |row|
    create(:salary_record,
      employee: employee_named(row["employee"]),
      base_salary: decimal_amount(row["base_salary"]),
      bonus: decimal_amount(row["bonus"]),
      allowance: decimal_amount(row["allowance"]),
      effective_date: parse_date(row["effective_date"])
    )
  end
end

# Setup for audit scenarios: a change made by the HR Manager through the UI, so
# the version carries source "manual" and the HR Manager as the actor.
Given(/^the salary for (\d{4}-\d{2}-\d{2}) for "([^"]*)" was updated to ([0-9.]+)(?: ([A-Z]{3}))? by the HR Manager$/) do |date, name, amount, _code|
  record = salary_record_for(name, date)

  as_hr_manager do
    record.update!(base_salary: decimal_amount(amount), bonus: 0, allowance: 0)
  end
end

When("the HR Manager views the current salary of {string}") do |name|
  get "/api/v1/employees/#{employee_named(name).id}/salary"
end

When("the HR Manager views the salary history of {string}") do |name|
  get "/api/v1/employees/#{employee_named(name).id}/salary/history"
  # A later request (e.g. the audit view in the BR-3 scenario) would overwrite
  # the last response, so the history payload is kept against the view.
  @salary_history_response = api_response
end

def salary_history_data
  if @salary_history_response
    JSON.parse(@salary_history_response.body)["data"]
  else
    api_data
  end
end

When("the HR Manager creates a salary for {string} with:") do |name, table|
  post "/api/v1/employees/#{employee_named(name).id}/salary", params: table.hashes.first
end

When(/^the HR Manager updates the salary effective from (\d{4}-\d{2}-\d{2}) for "([^"]*)" with:$/) do |date, name, table|
  patch "/api/v1/employees/#{employee_named(name).id}/salary/#{salary_record_id_for(name, date)}",
        params: table.hashes.first
end

Then(/^the current salary should be ([0-9.]+)(?: ([A-Z]{3}))? effective from (\d{4}-\d{2}-\d{2})$/) do |amount, code, date|
  expect(api_data).to be_present, "expected a current salary, got: #{api_response_body}"
  expect(decimal_amount(api_data["base_salary"])).to eq(decimal_amount(amount))
  expect(iso_date(api_data["effective_date"])).to eq(date)
  expect(api_currency_code).to eq(code) if code
end

Then("there should be no current salary for {string}") do |name|
  expect(api_status).to be_between(200, 299)
  expect(api_data).to be_nil, "expected no current salary for #{name}, got: #{api_response_body}"
end

Then(/^the employee "([^"]*)" should have exactly (\d+) salary records?$/) do |name, count|
  employee = employee_named(name)
  expect(SalaryRecord.where(employee_id: employee.id).count).to eq(count.to_i)
end

Then(/^the salary history should contain (\d+) records?$/) do |count|
  expect(salary_history_data.size).to eq(count.to_i)
end

Then("the salary history should be ordered by effective date descending") do
  dates = salary_history_data.map { |row| Date.iso8601(row["effective_date"].to_s) }
  expect(dates).to eq(dates.sort.reverse)
end

Then(/^the salary for (\d{4}-\d{2}-\d{2}) for "([^"]*)" should be ([0-9.]+)(?: ([A-Z]{3}))?$/) do |date, name, amount, code|
  record = salary_record_for(name, date)
  expect(record.base_salary).to eq(decimal_amount(amount))

  if code
    expect(employee_named(name).currency.code).to eq(code)
  end
end

Then(/^the salary for (\d{4}-\d{2}-\d{2}) for "([^"]*)" should not exist$/) do |date, name|
  employee = employee_named(name)
  record = SalaryRecord.find_by(employee_id: employee.id, effective_date: parse_date(date))
  expect(record).to be_nil, "expected no salary record effective #{date}, found #{record.inspect}"
end
