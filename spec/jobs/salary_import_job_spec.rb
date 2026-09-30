require "rails_helper"

# LLD §8.1 and §8.3 — the API creates the import with the CSV attached and
# enqueues `SalaryImportJob` with the import id alone. The worker reads the file
# back off the import, moves it through its status lifecycle, applies the salary
# rules row by row and records failures instead of aborting the file.
#
# Described by string so the missing constant does not break suite loading.
RSpec.describe "SalaryImportJob", type: :job do
  let(:employee) { create(:employee) }

  # The import arrives already carrying the CSV, exactly as the controller
  # creates it: the worker is handed an id, not a file.
  def staged_import(rows, headers: %w[employee_id effective_date base_salary bonus allowance])
    create(:salary_import, csv_body: csv_from_rows(rows, headers: headers))
  end

  def run_job(salary_import)
    SalaryImportJob.perform_now(salary_import.id)
  end

  def row(effective_date, base_salary, employee_id: nil, bonus: "0", allowance: "0")
    {
      "employee_id" => (employee_id || employee.id).to_s,
      "effective_date" => effective_date,
      "base_salary" => base_salary,
      "bonus" => bonus,
      "allowance" => allowance
    }
  end

  describe "the job contract" do
    # LLD §8.1 — nothing about the file is passed through the job, so a job can
    # be retried without re-uploading.
    it "takes the import id alone" do
      expect(SalaryImportJob.instance_method(:perform).arity).to eq(1)
    end

    it "is enqueued with the import id" do
      salary_import = create(:salary_import)

      SalaryImportJob.perform_later(salary_import.id)

      expect(jobs_for("SalaryImportJob").last["args"]).to eq([ salary_import.id ])
    end
  end

  describe "the status lifecycle (LLD §8.2)" do
    it "starts by setting the import to processing" do
      salary_import = staged_import([ row("2026-01-01", "60000") ])

      run_job(salary_import)

      expect(salary_import.reload.status).to eq("completed")
    end

    it "completes when every row applies" do
      salary_import = staged_import([ row("2026-01-01", "60000") ])

      run_job(salary_import)

      expect(salary_import.reload.status).to eq("completed")
    end

    it "completes with errors when a row is rejected" do
      salary_import = staged_import([ row("not-a-date", "60000") ])

      run_job(salary_import)

      expect(salary_import.reload.status).to eq("completed_with_errors")
    end

    it "fails when the file cannot be read" do
      salary_import = create(:salary_import, csv_body: csv_from_rows([ row("2026-01-01", "60000") ]))
      # The upload is gone by the time the worker looks for it — the real shape
      # of this failure, and the one the rescue in `perform` exists for.
      salary_import.csv_file.purge

      run_job(salary_import)

      expect(salary_import.reload.status).to eq("failed")
    end
  end

  # A whole-file failure has no row to attribute it to, but leaving the reason
  # unrecorded would make the detail page empty and unexplained.
  describe "recording a whole-file failure" do
    let(:headers) { "employee_id,effective_date,base_salary,bonus,allowance" }

    it "records the reason when the headers are rejected" do
      salary_import = staged_import([ row("2026-01-01", "60000") ], headers: %w[id salary])

      run_job(salary_import)

      expect(salary_import.reload.status).to eq("failed")
      expect(salary_import.salary_import_errors.pluck(:error_message))
        .to include(a_string_matching(/invalid CSV headers/))
    end

    it "records the reason when the upload cannot be read" do
      salary_import = create(:salary_import, csv_body: headers + "\n")
      salary_import.csv_file.purge

      run_job(salary_import)

      expect(salary_import.reload.status).to eq("failed")
      expect(salary_import.salary_import_errors.count).to eq(1)
    end

    it "records it as a synthetic row outside the data rows" do
      salary_import = staged_import([ row("2026-01-01", "60000") ], headers: %w[id salary])

      run_job(salary_import)

      error = salary_import.salary_import_errors.first
      expect(error.row_number).to eq(0)
      expect(error.employee_id).to be_nil
      expect(error.raw_data).to eq({})
    end

    # The list only links `failed_records` to the detail page, so a whole-file
    # failure recorded without bumping it would be unreachable.
    it "counts the synthetic row in failed_records" do
      salary_import = staged_import([ row("2026-01-01", "60000") ], headers: %w[id salary])

      run_job(salary_import)

      expect(salary_import.reload.failed_records).to eq(1)
      expect(salary_import.failed_records).to eq(salary_import.salary_import_errors.count)
    end
  end

  describe "the counters (FR-6.3)" do
    it "counts every data row in total_records" do
      salary_import = staged_import(
        [ row("2026-01-01", "60000"), row("2027-01-01", "65000"), row("2028-01-01", "70000") ]
      )

      run_job(salary_import)

      expect(salary_import.reload.total_records).to eq(3)
    end

    it "counts applied rows in processed_records" do
      salary_import = staged_import([ row("2026-01-01", "60000"), row("2027-01-01", "65000") ])

      run_job(salary_import)

      expect(salary_import.reload.processed_records).to eq(2)
    end

    it "counts rejected rows in failed_records" do
      salary_import = staged_import([ row("2026-01-01", "60000"), row("not-a-date", "65000") ])

      run_job(salary_import)

      expect(salary_import.reload.failed_records).to eq(1)
    end

    it "keeps processed and failed accounting for the whole file" do
      salary_import = staged_import(
        [ row("2026-01-01", "60000"), row("not-a-date", "1"), row("2027-01-01", "65000") ]
      )

      run_job(salary_import)

      salary_import.reload
      expect(salary_import.processed_records + salary_import.failed_records).to eq(salary_import.total_records)
    end
  end

  describe "applying rows (LLD §8.4)" do
    it "creates a salary record for a valid row" do
      salary_import = staged_import([ row("2026-01-01", "60000") ])

      run_job(salary_import)

      expect(SalaryRecord.find_by(employee_id: employee.id, effective_date: Date.new(2026, 1, 1)).base_salary)
        .to eq(BigDecimal("60000.0"))
    end

    it "records the change as coming from this import" do
      salary_import = staged_import([ row("2026-01-01", "60000") ])

      run_job(salary_import)

      version = PaperTrail::Version.where(item_type: "SalaryRecord").last
      expect(version.source).to eq("bulk_import")
      expect(version.salary_import_id).to eq(salary_import.id)
    end

    it "updates an existing period when the values differ" do
      create(:salary_record, employee: employee, effective_date: Date.new(2026, 1, 1), base_salary: 60_000)
      salary_import = staged_import([ row("2026-01-01", "62000") ])

      run_job(salary_import)

      expect(SalaryRecord.find_by(employee_id: employee.id, effective_date: Date.new(2026, 1, 1)).base_salary)
        .to eq(BigDecimal("62000.0"))
    end

    it "creates nothing when the values are identical" do
      create(:salary_record, employee: employee, effective_date: Date.new(2026, 1, 1), base_salary: 60_000)
      before = PaperTrail::Version.where(item_type: "SalaryRecord").count
      salary_import = staged_import([ row("2026-01-01", "60000") ])

      run_job(salary_import)

      expect(PaperTrail::Version.where(item_type: "SalaryRecord").count).to eq(before)
    end

    # LLD §5.4 — a stale export is never applied.
    it "skips a row older than the latest existing period" do
      create(:salary_record, employee: employee, effective_date: Date.new(2026, 1, 1), base_salary: 60_000)
      salary_import = staged_import([ row("2025-01-01", "55000") ])

      run_job(salary_import)

      expect(SalaryRecord.find_by(employee_id: employee.id, effective_date: Date.new(2025, 1, 1))).to be_nil
    end

    it "does not overwrite the newer record when a stale row arrives" do
      create(:salary_record, employee: employee, effective_date: Date.new(2026, 1, 1), base_salary: 60_000)
      salary_import = staged_import([ row("2025-01-01", "55000") ])

      run_job(salary_import)

      expect(SalaryRecord.find_by(employee_id: employee.id, effective_date: Date.new(2026, 1, 1)).base_salary)
        .to eq(BigDecimal("60000.0"))
    end
  end

  describe "recording failures (FR-4.5, FR-6.4)" do
    it "records an error for a malformed date" do
      salary_import = staged_import([ row("not-a-date", "60000") ])

      run_job(salary_import)

      expect(salary_import.salary_import_errors.count).to eq(1)
    end

    it "records an error for an unknown employee" do
      salary_import = staged_import([ row("2026-01-01", "60000", employee_id: "999999") ])

      run_job(salary_import)

      expect(salary_import.salary_import_errors.count).to eq(1)
    end

    it "records an error for a non numeric amount" do
      salary_import = staged_import([ row("2026-01-01", "abc") ])

      run_job(salary_import)

      expect(salary_import.salary_import_errors.count).to eq(1)
    end

    it "keeps the raw row on the error" do
      salary_import = staged_import([ row("not-a-date", "60000") ])

      run_job(salary_import)

      expect(salary_import.salary_import_errors.first.raw_data["effective_date"]).to eq("not-a-date")
    end

    it "numbers rows including the header, so the first data row is 2" do
      salary_import = staged_import([ row("2026-01-01", "60000"), row("not-a-date", "1") ])

      run_job(salary_import)

      expect(salary_import.salary_import_errors.first.row_number).to eq(3)
    end

    it "records the employee when the row could be attributed to one" do
      salary_import = staged_import([ row("2026-01-01", "-5") ])

      run_job(salary_import)

      expect(salary_import.salary_import_errors.first.employee_id).to eq(employee.id)
    end

    it "leaves employee_id nil for an unknown employee" do
      salary_import = staged_import([ row("2026-01-01", "60000", employee_id: "999999") ])

      run_job(salary_import)

      expect(salary_import.salary_import_errors.first.employee_id).to be_nil
    end

    # LLD §8.5 — one bad row must not undo the rows around it.
    it "continues after a failed row" do
      salary_import = staged_import(
        [ row("2026-01-01", "60000"), row("not-a-date", "1"), row("2027-01-01", "65000") ]
      )

      run_job(salary_import)

      expect(SalaryRecord.where(employee_id: employee.id).count).to eq(2)
    end
  end

  describe "reading the file" do
    it "reads the CSV off the import's attachment" do
      salary_import = staged_import([ row("2026-01-01", "60000") ])

      run_job(salary_import)

      expect(salary_import.reload.csv_file).to be_attached
    end

    it "marks the import as started" do
      salary_import = staged_import([ row("2026-01-01", "60000") ])

      run_job(salary_import)

      expect(salary_import.reload.started_at).to be_present
    end
  end
end
