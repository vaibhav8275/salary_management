class SalaryImportErrorBlueprint < Blueprinter::Base
  identifier :id

  fields :row_number, :error_message

  # Null when the row could not be resolved to an employee — a blank or unknown
  # employee_id is itself a reason for failure, so the column has to be allowed to
  # be empty rather than carrying a placeholder id.
  field :employee_id

  # The row exactly as it arrived, so the HR Manager can see what was actually in
  # the file rather than a re-rendering of it. JSONB columns arrive as a Hash and
  # are passed through untouched.
  field :raw_data

  field :created_at do |error|
    error.created_at&.iso8601
  end
end
