# Employee directory steps (REQUIREMENTS §3.1, FR-1.1 – FR-1.7).
#
# Search, filter and pagination parameters are not fixed by the LLD. The
# assumption is one `search` box (FR-1.3 covers searching by id *or* name in the
# same breath) plus `department`, `country`, `page` and `per_page` filters.
#
# LLD §2.1, §2.3 — the `department` and `country` columns name reference rows
# rather than free text, and the optional `currency` column states the currency
# the country is paid in. Employees are therefore placed in the departments and
# countries these steps resolve, and never carry a currency of their own.
Given("the following employees exist:") do |table|
  table.hashes.each do |row|
    create(
      :employee,
      first_name: row["first_name"],
      last_name: row["last_name"],
      email: row["email"],
      department: ReferenceData.department(row["department"]),
      country: ReferenceData.country(row["country"], row["currency"]),
      hire_date: parse_date(row["hire_date"])
    )
  end
end

Given('an employee {string} exists with currency {string}') do |name, code|
  first, last = name.split(/\s+/, 2)
  create(:employee, first_name: first, last_name: last, country: ReferenceData.country_paid_in(code))
end

Given('an employee {string} exists with department {string} and country {string}') do |name, department, country|
  first, last = name.split(/\s+/, 2)
  create(
    :employee,
    first_name: first,
    last_name: last,
    department: ReferenceData.department(department),
    country: ReferenceData.country(country)
  )
end

# "is paid in" is business language; LLD §2.3 is where the currency lives, so an
# employee is paid in a currency by being placed in a country paid in it.
Given('{string} is paid in {string}') do |name, code|
  employee_named(name).update!(country: ReferenceData.country_paid_in(code))
end

# Built with insert_all so the 10,000 employee scenario stays fast. The unique
# email index is satisfied by construction, and the reference rows are resolved
# once and passed as ids.
Given('{int} employees exist in department {string}') do |count, department|
  now = Time.current
  department_id = ReferenceData.department(department).id
  country_id = ReferenceData.country("United States").id
  rows = count.times.map do |index|
    {
      first_name: "Bulk",
      last_name: format("Employee%d", index),
      email: "bulk#{index}@example.com",
      department_id: department_id,
      country_id: country_id,
      hire_date: Date.new(2020, 1, 1),
      created_at: now,
      updated_at: now
    }
  end

  Employee.insert_all!(rows)
end

When("the HR Manager lists employees") do
  get "/api/v1/employees"
end

When("the HR Manager lists employees on page {int} with {int} per page") do |page, per_page|
  get "/api/v1/employees", params: { page: page, per_page: per_page }
end

When("the HR Manager searches employees for {string}") do |term|
  get "/api/v1/employees", params: { search: term }
end

When("the HR Manager searches employees for the employee id of {string}") do |name|
  get "/api/v1/employees", params: { search: employee_named(name).id.to_s }
end

When("the HR Manager filters employees by department {string}") do |department|
  get "/api/v1/employees", params: { department: department }
end

When("the HR Manager filters employees by country {string}") do |country|
  get "/api/v1/employees", params: { country: country }
end

When("the HR Manager filters employees by department {string} and country {string}") do |department, country|
  get "/api/v1/employees", params: { department: department, country: country }
end

When("the HR Manager opens the employee {string}") do |name|
  get "/api/v1/employees/#{employee_named(name).id}"
end

When("the HR Manager opens employee {int}") do |id|
  get "/api/v1/employees/#{id}"
end

Then(/^the employee list should contain (\d+) employees?$/) do |count|
  expect(api_data.size).to eq(count.to_i)
end

Then("the employee list should include the employee id and name") do
  expect(employee_payloads).to all(include("id", "first_name", "last_name"))
  expect(employee_payloads.map { |row| row["id"] }).to all(be_a(Integer))
end

Then('the employee {string} should be in the employee list') do |name|
  expect(names_in_employee_list).to include(name)
end

Then('the employee {string} should not be in the employee list') do |name|
  expect(names_in_employee_list).not_to include(name)
end

Then('the employee {string} should have department {string}') do |name, department|
  expect(employee_attribute(name, "department")).to eq(department)
end

Then('the employee {string} should have country {string}') do |name, country|
  expect(employee_attribute(name, "country")).to eq(country)
end

Then('the employee {string} should have hire date {string}') do |name, hire_date|
  expect(iso_date(employee_attribute(name, "hire_date"))).to eq(hire_date)
end

Then('the employee {string} should have email {string}') do |name, email|
  expect(employee_attribute(name, "email")).to eq(email)
end

Then('the employee detail should show email {string}') do |email|
  expect(api_data["email"]).to eq(email)
end

Then('the employee detail should show the currency {string}') do |code|
  expect(api_currency_code).to eq(code)
end

Then("the pagination meta should report page {int}") do |page|
  expect(api_meta["current_page"]).to eq(page)
end

Then("the pagination meta should report {int} per page") do |per_page|
  expect(api_meta["per_page"]).to eq(per_page)
end

Then("the pagination meta should report {int} total records") do |total|
  expect(api_meta["total_count"]).to eq(total)
end

Then("the pagination meta should report {int} total pages") do |pages|
  expect(api_meta["total_pages"]).to eq(pages)
end

module EmployeeStepHelpers
  def names_in_employee_list
    employee_payloads.map { |row| "#{row['first_name']} #{row['last_name']}" }
  end

  def employee_attribute(name, key)
    payload = find_employee_payload(name)
    raise "expected #{name.inspect} in the response, got: #{api_response_body}" if payload.nil?

    payload[key]
  end

  def iso_date(value)
    return nil if value.nil?
    return value.iso8601 if value.respond_to?(:iso8601)

    value.to_s
  end
end

World(EmployeeStepHelpers)
