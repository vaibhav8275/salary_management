require "bigdecimal"
require "bigdecimal/util"

# Per-scenario storage and the parsing helpers shared by the step definitions.
#
# Two conventions matter here:
#
# 1. Given steps build fixtures through the model layer, not the API. Scenarios
#    therefore fail on the behaviour under test rather than on setup, and can be
#    read without knowing the HTTP contract.
# 2. Then steps that assert system state (salary periods, import counters, audit
#    versions) read the database directly. Steps that assert a response assert
#    on the last response from the API.
module ScenarioState
  # Files staged for upload, keyed by filename.
  attr_accessor :scenario_files

  # The SalaryImport produced by the most recent upload.
  attr_accessor :last_import

  def reset_scenario_state!
    @scenario_files = {}
    @last_import = nil
  end

  def stage_file(filename, content, content_type)
    @scenario_files[filename] = { content: content, content_type: content_type }
  end

  def staged_file(filename)
    @scenario_files.fetch(filename) do
      raise "Test setup error: no file named #{filename.inspect} was staged for this scenario. " \
            "Staged files: #{@scenario_files.keys.inspect}"
    end
  end

  def last_import!
    raise "No import has been created in this scenario" if @last_import.nil?

    @last_import
  end

  def employee_named(name)
    first, last = name.to_s.strip.split(/\s+/, 2)
    employee = Employee.find_by(first_name: first, last_name: last)
    raise "Test setup error: no employee named #{name.inspect} exists in this scenario" if employee.nil?

    employee
  end

  def parse_date(value)
    Date.parse(value.to_s)
  rescue Date::Error
    raise "Test setup error: #{value.inspect} is not a parseable date"
  end

  # Deliberately strict: a silently coerced 0 in test setup would turn a real
  # failure into a false pass.
  def decimal_amount(value)
    string = value.to_s.strip
    raise "Test setup error: #{value.inspect} is not a numeric amount" unless string.match?(/\A-?\d+(\.\d+)?\z/)

    BigDecimal(string)
  end

  def salary_record_for(name, effective_date)
    employee = employee_named(name)
    record = SalaryRecord.find_by(employee_id: employee.id, effective_date: parse_date(effective_date))
    raise "Test setup error: #{name.inspect} has no salary record effective #{effective_date}" if record.nil?

    record
  end

  # LLD §3 — editing a period that holds no record has to be rejected. The
  # documented update path carries a record id, so a period with no record is
  # addressed with an id that cannot exist. The request stays well formed, and
  # the scenarios assert that no record is created for the period.
  def salary_record_id_for(name, effective_date)
    employee = employee_named(name)
    SalaryRecord.find_by(employee_id: employee.id, effective_date: parse_date(effective_date))&.id || 0
  end

  def employee_full_name(employee)
    "#{employee.first_name} #{employee.last_name}"
  end

  def employee_payloads(payload = api_data)
    Array(payload)
  end

  def find_employee_payload(name)
    employee = employee_named(name)

    employee_payloads.find do |row|
      row.is_a?(Hash) && row["id"] == employee.id
    end || employee_payloads.find do |row|
      row.is_a?(Hash) && "#{row['first_name']} #{row['last_name']}" == name
    end
  end

  # Every PaperTrail version belonging to an employee's salary records.
  def versions_for_employee(name)
    employee = employee_named(name)
    record_ids = SalaryRecord.where(employee_id: employee.id).select(:id)

    PaperTrail::Version
      .where(item_type: "SalaryRecord", item_id: record_ids)
      .order(:id)
  end

  # Every base_salary value a version mentions, as a new value in a changeset or
  # as the state captured on a create.
  def version_amounts(versions)
    versions.flat_map do |version|
      amounts = []
      changeset = version.changeset
      amounts << changeset["base_salary"]&.last if changeset.is_a?(Hash) && changeset.key?("base_salary")
      amounts << version.object["base_salary"] if version.object.is_a?(Hash) && version.object.key?("base_salary")
      amounts
    end.map { |amount| BigDecimal(amount.to_s) }
  end

  def import_error_for(row_number)
    last_import!.salary_import_errors.find_by(row_number: row_number)
  end
end

World(ScenarioState)
