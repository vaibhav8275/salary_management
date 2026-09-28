require "bigdecimal"
require "bigdecimal/util"

class SalaryImportJob < ApplicationJob
  queue_as :default

  def perform(import_id)
    @import = SalaryImport.find(import_id)

    run
  rescue StandardError
    @import.update!(status: :failed) if @import.persisted?
  end

  private

  def run
    @import.update!(status: :processing, started_at: Time.current)

    csv = S3StorageService.new.download(@import.s3_object_key)
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
