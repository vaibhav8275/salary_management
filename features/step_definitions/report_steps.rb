# Reporting steps (REQUIREMENTS §3.7, FR-7.1 – FR-7.5, BR-8; LLD §11).
#
# Report paths are not specified in the LLD, so the assumed surface is:
#
#   GET /api/v1/reports/average-salary-by-department
#   GET /api/v1/reports/salary-distribution
#   GET /api/v1/reports/total-payroll-by-country
#   GET /api/v1/reports/salary-trends
#   GET /api/v1/reports/employee-counts?group_by=department|country
#
# All of them accept the same optional filters: from, to, department, country.
When("the HR Manager requests the average salary by department") do
  get "#{reports_path}/average-salary-by-department"
end

When("the HR Manager requests the average salary by department for department {string}") do |department|
  get "#{reports_path}/average-salary-by-department", params: { department: department }
end

When("the HR Manager requests the average salary by department for country {string}") do |country|
  get "#{reports_path}/average-salary-by-department", params: { country: country }
end

When(/^the HR Manager requests the average salary by department between (\d{4}-\d{2}-\d{2}) and (\d{4}-\d{2}-\d{2})$/) do |from, to|
  get "#{reports_path}/average-salary-by-department", params: { from: from, to: to }
end

When("the HR Manager requests the salary distribution") do
  get "#{reports_path}/salary-distribution"
end

When("the HR Manager requests the salary distribution for department {string}") do |department|
  get "#{reports_path}/salary-distribution", params: { department: department }
end

When("the HR Manager requests the total payroll by country") do
  get "#{reports_path}/total-payroll-by-country"
end

When("the HR Manager requests the salary trends") do
  get "#{reports_path}/salary-trends"
end

When("the HR Manager requests the salary trends for department {string}") do |department|
  get "#{reports_path}/salary-trends", params: { department: department }
end

When(/^the HR Manager requests the salary trends for department "([^"]*)" between (\d{4}-\d{2}-\d{2}) and (\d{4}-\d{2}-\d{2})$/) do |department, from, to|
  get "#{reports_path}/salary-trends", params: { department: department, from: from, to: to }
end

When("the HR Manager requests employee counts by department") do
  get "#{reports_path}/employee-counts", params: { group_by: "department" }
end

When("the HR Manager requests employee counts by country") do
  get "#{reports_path}/employee-counts", params: { group_by: "country" }
end

When("the HR Manager requests employee counts by department for department {string}") do |department|
  get "#{reports_path}/employee-counts", params: { group_by: "department", department: department }
end

Then(/^the average salary for department "([^"]*)" in "([A-Z]{3})" should be ([0-9.]+)$/) do |department, code, amount|
  expect_average_for(department, amount, code)
end

Then(/^the average salary for department "([^"]*)" should be ([0-9.]+) ([A-Z]{3})$/) do |department, amount, code|
  expect_average_for(department, amount, code)
end

Then(/^the total payroll for country "([^"]*)" in "([A-Z]{3})" should be ([0-9.]+)$/) do |country, code, amount|
  expect_total_for(country, amount, code)
end

Then(/^the total payroll for country "([^"]*)" should be ([0-9.]+) ([A-Z]{3})$/) do |country, amount, code|
  expect_total_for(country, amount, code)
end

Then(/^the employee count for department "([^"]*)" should be (\d+)$/) do |department, count|
  expect(count_for_group("department", department)).to eq(count.to_i)
end

Then(/^the employee count for country "([^"]*)" should be (\d+)$/) do |country, count|
  expect(count_for_group("country", country)).to eq(count.to_i)
end

Then(/^the salary distribution should account for (\d+) employees? in total$/) do |total|
  counts = report_rows.map { |row| row[:count] }.compact
  raise "the distribution reported no counts: #{api_response_body}" if counts.empty?

  expect(counts.sum).to eq(total.to_i)
end

Then("every reported monetary figure should state a currency") do
  rows = report_rows
  raise "expected the report to contain rows, got: #{api_response_body}" if rows.empty?

  rows.each do |row|
    expect(row[:currency]).to be_present,
                             "report row #{row[:raw].inspect} states no currency (BR-8)"
  end
end

Then(/^the salary trend should report an average of ([0-9.]+) effective from (\d{4}-\d{2}-\d{2})$/) do |amount, date|
  row = trend_rows.find { |candidate| candidate[:date] == date }
  raise "expected a trend point for #{date}, got #{api_response_body}" if row.nil?

  expect(decimal_amount(row[:amount])).to eq(decimal_amount(amount))
end

Then(/^the salary trend should report no average of ([0-9.]+) effective from (\d{4}-\d{2}-\d{2})$/) do |amount, date|
  row = trend_rows.find { |candidate| candidate[:date] == date }
  if row
    expect(decimal_amount(row[:amount])).not_to eq(decimal_amount(amount))
  end
end

Then("the report should be empty") do
  expect(api_data).to eq([])
end

Then(/^the report should contain (\d+) entr(?:y|ies)$/) do |count|
  expect(api_data.size).to eq(count.to_i)
end

module ReportStepHelpers
  def reports_path
    "/api/v1/reports"
  end

  def report_rows
    @report_rows ||= Array(api_data).map do |row|
      raise "expected report rows to be objects, got: #{row.inspect}" unless row.is_a?(Hash)

      {
        raw: row,
        group: row["department"] || row["country"] || row["group"] || row["name"] || row["label"],
        currency: report_currency(row),
        amount: report_amount(row),
        count: row["count"] || row["employee_count"] || row["employees"]
      }
    end
  end

  def trend_rows
    Array(api_data).filter_map do |row|
      next unless row.is_a?(Hash)

      date = row["effective_date"] || row["date"]
      next if date.nil?

      {
        raw: row,
        date: date.to_s,
        currency: report_currency(row),
        amount: report_amount(row)
      }
    end
  end

  def report_currency(row)
    currency = row["currency"]
    return currency["code"] if currency.is_a?(Hash)

    row["currency_code"] || currency
  end

  # Report value keys are not fixed by the LLD, so the amount is whichever
  # numeric field carries the reported figure.
  def report_amount(row)
    key = row.keys.find { |candidate| candidate.match?(/average|avg|total|amount|value/) }
    key && row[key]
  end

  def count_for_group(grouping, value)
    row = report_rows.find { |candidate| candidate[:group] == value }
    raise "expected a #{grouping} row for #{value.inspect}, got #{api_response_body}" if row.nil?

    row[:count]
  end

  def expect_average_for(department, amount, code)
    expect_group_amount("department", department, amount, code)
  end

  def expect_total_for(country, amount, code)
    expect_group_amount("country", country, amount, code)
  end

  def expect_group_amount(grouping, group, amount, code)
    row = report_rows.find do |candidate|
      candidate[:group] == group && candidate[:currency] == code
    end

    if row.nil?
      raise "expected a #{grouping} row for #{group.inspect} in #{code}, got #{api_response_body}"
    end

    expect(decimal_amount(row[:amount])).to eq(decimal_amount(amount))
  end
end

World(ReportStepHelpers)
