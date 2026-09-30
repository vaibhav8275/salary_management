require "bigdecimal"
require "bigdecimal/util"

class SalaryImportJob < ApplicationJob
  queue_as :default

  def perform(import_id)
    @import = SalaryImport.find(import_id)

    run
  rescue StandardError => error
    record_file_failure(error)
  end

  private

  # A failure that stops the whole file — unparseable upload, headers the
  # validator rejects, anything that raises before or during parsing — has no row
  # to attribute it to, but the HR Manager still has to be told why. It is
  # recorded as a single synthetic error at `row_number` 0, which the detail page
  # renders as a file-level banner rather than a CSV line.
  #
  # `failed_records` is incremented alongside it so the two stay equal: the list
  # only links that count to the detail page, so a whole-file failure recorded
  # without bumping it would be unreachable.
  def record_file_failure(error)
    return unless @import&.persisted?

    @import.salary_import_errors.create!(
      row_number: 0,
      employee_id: nil,
      error_message: "#{error.class}: #{error.message}",
      raw_data: {}
    )
    @import.update!(status: :failed, failed_records: @import.failed_records + 1)
  end

  def run
    @import.update!(status: :processing, started_at: Time.current)

    csv = @import.csv_contents
    rows = parse(csv)
    headers = rows.shift
    raise ArgumentError, "invalid CSV headers" unless CsvRowValidator.new.valid_headers?(headers)

    provenance = { whodunnit: "HR Manager", controller_info: { source: "bulk_import", salary_import_id: @import.id } }
    processed = 0
    failed = 0
    skipped = 0

    PaperTrail.request(provenance) do
      rows.each_with_index do |cells, index|
        row = headers.zip(cells).to_h
        line_number = index + 2
        result = CsvRowValidator.new.validate(row)

        if result.valid?
          outcome = SalaryService.new.apply_imported_salary(
            result.employee,
            base_salary: result.base_salary,
            bonus: result.bonus,
            allowance: result.allowance,
            effective_date: result.effective_date
          )

          if outcome.skipped?
            record_error(
              line_number,
              result,
              "Skipped: the effective date is earlier than the latest recorded salary"
            )
            skipped += 1
          else
            processed += 1
          end
        else
          record_error(line_number, result, result.error_message)
          failed += 1
        end
      end
    end

    finalize(rows.size, processed, failed, skipped)
  end

  def parse(body)
    body.to_s.split("\n").reject(&:blank?).map { |line| line.split(",", -1) }
  end

  def record_error(line_number, result, message)
    @import.salary_import_errors.create!(
      row_number: line_number,
      employee_id: result.employee&.id,
      error_message: message,
      raw_data: result.raw_data
    )
  end

  def finalize(total, processed, failed, skipped)
    status = failed.zero? ? :completed : :completed_with_errors
    @import.update!(
      status: status,
      total_records: total,
      processed_records: processed,
      failed_records: failed + skipped
    )
  end
end
