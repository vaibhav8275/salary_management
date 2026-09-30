# Audit history steps
# (REQUIREMENTS FR-2.5, BR-3, BR-4; LLD §7).
#
# Count and changeset assertions read the versions table directly, so they work
# both as preconditions and as outcomes. The "should report ..." steps assert on
# the last response from GET /api/v1/employees/:id/salary/audit, which keeps the
# endpoint itself under test.
When("the HR Manager views the audit history of {string}") do |name|
  @audit_employee_name = name
  get "/api/v1/employees/#{employee_named(name).id}/salary/audit"
end

Then(/^the audit history for "([^"]*)" contains (\d+) entr(?:y|ies)$/) do |name, count|
  expect(versions_for_employee(name).count).to eq(count.to_i)
end

Then("the audit history for {string} is grouped by salary record") do |name|
  groups = audit_groups
  # Cucumber's step definitions are not RSpec examples, so `all` here is a plain
  # check rather than the matcher of the same name.
  malformed = groups.reject { |group| group.key?("salary_record_id") && group.key?("versions") }
  expect(malformed).to be_empty,
                       "expected every group to name its record and carry its versions, got: #{api_response_body}"

  record_ids = employee_named(name).salary_records.pluck(:id)
  foreign = groups.map { |group| group["salary_record_id"] } - record_ids
  expect(foreign).to be_empty,
                     "expected only this employee's records, got: #{foreign.inspect} in #{api_response_body}"
end

Then(/^the audit history group for (\d{4}-\d{2}-\d{2}) for "([^"]*)" contains (\d+) entr(?:y|ies)$/) do |date, name, count|
  expect(audit_group_for_effective_date(name, date)["versions"].size).to eq(count.to_i)
end

Then(/^the audit history for "([^"]*)" should not contain a change to ([0-9.]+)$/) do |name, _amount|
  # A no-op must not produce an update version at all, so any update event for
  # this employee is a failure regardless of the amount involved.
  expect(versions_for_employee(name).map(&:event)).not_to include("update")
end

Then("the audit history should include a change to {float}") do |amount|
  # version_amounts normalises amounts to their JSON-numeric string form (e.g.
  # "60000.0"), so the expected figure is normalised the same way.
  expect(version_amounts(versions_for_audited_employee)).to include(BigDecimal(amount.to_s).to_s("F"))
end

Then(/^the audit history should report the change from ([0-9.]+) to ([0-9.]+)$/) do |from, to|
  expected = [ decimal_amount(from), decimal_amount(to) ]

  expect(audit_changesets).to include(expected),
                             "expected a changeset of #{expected.inspect}, got #{audit_changesets.inspect}"
end

Then('the audit history should report the actor {string}') do |actor|
  expect(latest_audit_entry["whodunnit"]).to eq(actor)
end

Then('the audit history should report source {string}') do |source|
  expect(latest_audit_entry["source"]).to eq(source)
end

Then(/^the audit history entry should be an "([^"]*)" event$/) do |event|
  expect(latest_audit_entry["event"]).to eq(event)
end

Then("the audit history should report a change time") do
  expect(latest_audit_entry["created_at"]).to be_present
end

Then("the audit history should report the import id") do
  expect(latest_audit_entry["salary_import_id"]).to eq(last_import!.id)
end

module AuditStepHelpers
  def versions_for_audited_employee
    name = @audit_employee_name
    raise "Test setup error: the scenario never fetched an audit history" if name.nil?

    versions_for_employee(name)
  end

  # The response is one group per salary record, so the steps that describe a
  # single entry read through the group of the record under test rather than off
  # the top-level array. Salary history is a flat list per employee and the audit
  # groups are keyed by record id, so the record is found the same way here.
  def audit_groups
    Array(api_data)
  end

  def audit_entries
    audit_groups.flat_map { |group| Array(group["versions"]) }
  end

  # The group belonging to one salary record, addressed the way a scenario
  # names it: by the effective date rather than by the id it does not know.
  def audit_group_for_effective_date(name, effective_date)
    record = SalaryRecord.find_by!(
      employee: employee_named(name),
      effective_date: Date.parse(effective_date)
    )
    group = audit_groups.detect { |candidate| candidate["salary_record_id"] == record.id }
    raise "no audit group for #{effective_date}, got: #{api_response_body}" if group.nil?

    group
  end

  # Newest entry regardless of the order the endpoint chooses to return them in.
  def latest_audit_entry
    entries = audit_entries.sort_by { |entry| [ entry["created_at"].to_s, entry["id"].to_i ] }
    raise "expected an audit entry in the response, got: #{api_response_body}" if entries.empty?

    entries.last
  end

  def audit_changesets
    audit_entries.filter_map do |entry|
      changeset = entry["changeset"]
      next unless changeset.is_a?(Hash) && changeset.key?("base_salary")

      pair = changeset["base_salary"]
      next unless pair.is_a?(Array) && pair.size == 2

      [ decimal_amount(pair.first), decimal_amount(pair.last) ]
    end
  end
end

World(AuditStepHelpers)
