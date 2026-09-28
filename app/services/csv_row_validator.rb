require "bigdecimal"
require "bigdecimal/util"

class CsvRowValidator
  REQUIRED_HEADERS = %w[employee_id effective_date base_salary].freeze

  Result = Struct.new(:valid?, :employee, :base_salary, :bonus, :allowance,
                      :effective_date, :raw_data, :error_message, keyword_init: true)

  def valid?(row)
    validate(row).valid?
  end

  def validate(row)
    row = row || {}
    @row = row
    @employee = nil

    catch(:invalid) do
      employee = validate_employee(row)
      effective_date = validate_date(row)
      base_salary = validate_amount(row, "base_salary", required: true)
      bonus = validate_amount(row, "bonus")
      allowance = validate_amount(row, "allowance")

      return Result.new(
        valid?: true,
        employee: employee,
        base_salary: base_salary,
        bonus: bonus,
        allowance: allowance,
        effective_date: effective_date,
        raw_data: row,
        error_message: nil
      )
    end
  end

  def valid_headers?(headers)
    required = REQUIRED_HEADERS

    headers.present? && required.all? { |header| headers.include?(header) }
  end

  private

  def validate_employee(row)
    raw = row["employee_id"].to_s
    return invalid("Missing employee_id") if raw.blank?

    employee = Employee.find_by(id: raw)
    return invalid("Unknown employee #{raw}") if employee.nil?

    @employee = employee
    employee
  end

  def validate_date(row)
    raw = row["effective_date"].to_s
    return invalid("Missing effective_date") if raw.blank?

    Date.iso8601(raw)
  rescue ArgumentError
    invalid("Invalid effective_date '#{raw}'")
  end

  def validate_amount(row, column, required: false)
    raw = row[column].to_s
    return BigDecimal("0") if raw.blank? && !required
    return invalid("Missing #{column}") if raw.blank?

    amount = BigDecimal(raw)
    return invalid("#{column} must be non-negative") if amount.negative?

    amount
  rescue ArgumentError
    invalid("Invalid #{column} '#{raw}'")
  end

  def invalid(message)
    throw(:invalid, Result.new(
      valid?: false,
      employee: @employee,
      base_salary: nil,
      bonus: nil,
      allowance: nil,
      effective_date: nil,
      raw_data: @row,
      error_message: message
    ))
  end
end
