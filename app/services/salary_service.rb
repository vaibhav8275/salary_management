require "bigdecimal"
require "bigdecimal/util"

class SalaryService
  HR_MANAGER = "HR Manager".freeze
  SOURCE_MANUAL = "manual".freeze

  class Outcome
    attr_reader :record

    def initialize(record:, persisted:, skipped:)
      @record = record
      @persisted = persisted
      @skipped = skipped
    end

    def persisted?
      @persisted
    end

    def skipped?
      @skipped
    end
  end

  def current_salary_record(employee)
    employee.salary_records
            .where("salary_records.effective_date <= ?", Date.current)
            .order(effective_date: :desc)
            .first
  end

  def create_salary_record(employee, base_salary:, bonus: 0, allowance: 0, effective_date:)
    record = employee.salary_records.new(
      base_salary: base_salary,
      bonus: bonus,
      allowance: allowance,
      effective_date: effective_date
    )
    record.save
    record
  end

  def update_salary_record(record, base_salary: record.base_salary, bonus: record.bonus, allowance: record.allowance)
    return record if unchanged?(record, base_salary, bonus, allowance)

    record.assign_attributes(base_salary: base_salary, bonus: bonus, allowance: allowance)

    unless record.valid?
      record.restore_attributes
      return record.dup
    end

    record.save
    record
  end

  def apply_imported_salary(employee, base_salary:, bonus: 0, allowance: 0, effective_date:)
    latest = latest_salary_record(employee)

    if latest.nil? || effective_date > latest.effective_date
      record = create_salary_record(employee, base_salary: base_salary, bonus: bonus, allowance: allowance, effective_date: effective_date)
      return Outcome.new(record: record, persisted: record.persisted?, skipped: false)
    end

    return Outcome.new(record: nil, persisted: false, skipped: true) if effective_date < latest.effective_date

    return Outcome.new(record: latest, persisted: true, skipped: false) if unchanged?(latest, base_salary, bonus, allowance)

    record = update_salary_record(latest, base_salary: base_salary, bonus: bonus, allowance: allowance)
    Outcome.new(record: record, persisted: record.persisted?, skipped: false)
  end

  def revert_salary_change(version)
    return if version.nil?

    previous = version.reify
    return if previous.nil?

    record = version.item
    return if record.nil?

    PaperTrail.request(whodunnit: HR_MANAGER, controller_info: { source: SOURCE_MANUAL }) do
      record.update!(
        base_salary: previous.base_salary,
        bonus: previous.bonus,
        allowance: previous.allowance
      )
    end

    record
  end

  private

  def latest_salary_record(employee)
    employee.salary_records.order(effective_date: :desc).first
  end

  def unchanged?(record, base_salary, bonus, allowance)
    record.base_salary == to_decimal(base_salary) &&
      record.bonus == to_decimal(bonus) &&
      record.allowance == to_decimal(allowance)
  end

  def to_decimal(value)
    return value if value.is_a?(BigDecimal)

    BigDecimal(value.to_s)
  rescue ArgumentError
    value
  end
end
