require "rails_helper"

# LLD §5 and §6 — the salary rules live in one place and both the UI path and
# the bulk import path go through them.
#
# The service is described by name rather than by constant on purpose: none of
# these classes exist yet, and a `describe SomeMissingConstant` block would blow
# up while the suite loads and take every other spec file down with it. Naming it
# as a string keeps the rest of the suite runnable and turns the missing class
# into one red example per rule instead.
#
# The method names come from LLD §6. Their arguments are not specified, so each
# example states the assumption it relies on.
RSpec.describe "SalaryService", type: :service do
  let(:service) { SalaryService.new }
  let(:employee) { create(:employee) }

  describe "#current_salary_record" do
    # LLD §5.1 — the record with the latest effective date that is not in the
    # future.
    it "returns the latest record" do
      create(:salary_record, employee: employee, effective_date: Date.new(2024, 1, 1), base_salary: 40_000)
      latest = create(:salary_record, employee: employee, effective_date: Date.new(2025, 1, 1), base_salary: 50_000)

      expect(service.current_salary_record(employee)).to eq(latest)
    end

    it "ignores a future dated record" do
      create(:salary_record, employee: employee, effective_date: Date.new(2025, 1, 1), base_salary: 50_000)
      create(:salary_record, employee: employee, effective_date: 1.year.from_now.to_date, base_salary: 70_000)

      expect(service.current_salary_record(employee).base_salary).to eq(BigDecimal("50000.0"))
    end

    it "returns nil when the employee has no salary" do
      expect(service.current_salary_record(employee)).to be_nil
    end

    it "returns nil when every record is future dated" do
      create(:salary_record, employee: employee, effective_date: 1.year.from_now.to_date, base_salary: 70_000)

      expect(service.current_salary_record(employee)).to be_nil
    end

    it "does not return another employee's record" do
      create(:salary_record, employee: create(:employee), effective_date: Date.new(2025, 1, 1), base_salary: 50_000)

      expect(service.current_salary_record(employee)).to be_nil
    end
  end

  describe "#create_salary_record" do
    # LLD §5.2 — a newer effective date creates a new period and leaves the
    # earlier one intact.
    it "creates a new period" do
      existing = create(:salary_record, employee: employee, effective_date: Date.new(2026, 1, 1), base_salary: 60_000)

      result = service.create_salary_record(
        employee,
        base_salary: 65_000, bonus: 0, allowance: 0, effective_date: Date.new(2027, 1, 1)
      )

      expect(result).to be_persisted
      expect(records_for(employee).count).to eq(2)
      expect(existing.reload.base_salary).to eq(BigDecimal("60000.0"))
    end

    it "writes a manual audit version" do
      as_hr_manager do
        service.create_salary_record(
          employee,
          base_salary: 65_000, bonus: 0, allowance: 0, effective_date: Date.new(2027, 1, 1)
        )
      end

      expect(latest_version_for(SalaryRecord.last).source).to eq("manual")
    end

    it "reports a validation failure for a negative amount" do
      result = service.create_salary_record(
        employee,
        base_salary: -1, bonus: 0, allowance: 0, effective_date: Date.new(2027, 1, 1)
      )

      expect(result).not_to be_persisted
      expect(records_for(employee).count).to eq(0)
    end

    it "refuses a period that already exists" do
      create(:salary_record, employee: employee, effective_date: Date.new(2026, 1, 1), base_salary: 60_000)

      service.create_salary_record(
        employee,
        base_salary: 70_000, bonus: 0, allowance: 0, effective_date: Date.new(2026, 1, 1)
      )

      expect(records_for(employee).count).to eq(1)
    end
  end

  describe "#update_salary_record" do
    let(:record) { create(:salary_record, employee: employee, effective_date: Date.new(2026, 1, 1), base_salary: 60_000) }

    # LLD §5.3 — same period, different values: update in place.
    it "updates the existing period" do
      service.update_salary_record(record, base_salary: 62_000, bonus: 250, allowance: 100)

      expect(records_for(employee).count).to eq(1)
      expect(record.reload.base_salary).to eq(BigDecimal("62000.0"))
    end

    it "keeps the effective date" do
      service.update_salary_record(record, base_salary: 62_000)

      expect(record.reload.effective_date).to eq(Date.new(2026, 1, 1))
    end

    # LLD §5.3 — identical values are a no-op and write no version.
    it "writes no version when the values are identical" do
      before = version_count_for(record)

      service.update_salary_record(record, base_salary: 60_000, bonus: 0, allowance: 0)

      expect(version_count_for(record)).to eq(before)
    end

    it "writes a version when one amount changes" do
      before = version_count_for(record)

      service.update_salary_record(record, base_salary: 60_000, bonus: 0, allowance: 1)

      expect(version_count_for(record)).to eq(before + 1)
    end

    it "writes a version when only the bonus changes" do
      create(:salary_record, employee: employee, effective_date: Date.new(2024, 1, 1))
      before = version_count_for(record)

      service.update_salary_record(record, base_salary: 60_000, bonus: 500, allowance: 0)

      expect(version_count_for(record)).to eq(before + 1)
    end

    it "rejects a negative amount without changing the record" do
      result = service.update_salary_record(record, base_salary: -1)

      expect(result).not_to be_persisted
      expect(record.reload.base_salary).to eq(BigDecimal("60000.0"))
    end
  end

  describe "#apply_imported_salary" do
    # LLD §8.4 — the worked example, one row at a time.
    let(:existing) { create(:salary_record, employee: employee, effective_date: Date.new(2026, 1, 1), base_salary: 60_000) }

    it "creates a new period for a newer effective date" do
      salary_import = create(:salary_import)

      as_bulk_import(salary_import) do
        service.apply_imported_salary(
          employee,
          base_salary: 65_000, bonus: 0, allowance: 0, effective_date: Date.new(2027, 1, 1)
        )
      end

      expect(records_for(employee).count).to eq(2)
    end

    it "updates the period when the values differ" do
      salary_import = create(:salary_import)

      as_bulk_import(salary_import) do
        service.apply_imported_salary(
          employee,
          base_salary: 62_000, bonus: 0, allowance: 0, effective_date: Date.new(2026, 1, 1)
        )
      end

      expect(records_for(employee).count).to eq(1)
      expect(existing.reload.base_salary).to eq(BigDecimal("62000.0"))
    end

    it "writes no version for identical values" do
      salary_import = create(:salary_import)
      before = version_count_for(existing)

      as_bulk_import(salary_import) do
        service.apply_imported_salary(
          employee,
          base_salary: 60_000, bonus: 0, allowance: 0, effective_date: Date.new(2026, 1, 1)
        )
      end

      expect(version_count_for(existing)).to eq(before)
    end

    it "attributes the version to the import" do
      salary_import = create(:salary_import)

      as_bulk_import(salary_import) do
        service.apply_imported_salary(
          employee,
          base_salary: 62_000, bonus: 0, allowance: 0, effective_date: Date.new(2026, 1, 1)
        )
      end

      version = latest_version_for(existing)

      expect(version.source).to eq("bulk_import")
      expect(version.salary_import_id).to eq(salary_import.id)
    end

    # LLD §5.4 — a stale export never overwrites newer salary information.
    it "skips a stale effective date" do
      salary_import = create(:salary_import)

      result = as_bulk_import(salary_import) do
        service.apply_imported_salary(
          employee,
          base_salary: 55_000, bonus: 0, allowance: 0, effective_date: Date.new(2025, 1, 1)
        )
      end

      expect(result).not_to be_persisted
      expect(records_for(employee).count).to eq(1)
      expect(existing.reload.base_salary).to eq(BigDecimal("60000.0"))
    end

    it "reports the stale row as skipped" do
      salary_import = create(:salary_import)

      outcome = as_bulk_import(salary_import) do
        service.apply_imported_salary(
          employee,
          base_salary: 55_000, bonus: 0, allowance: 0, effective_date: Date.new(2025, 1, 1)
        )
      end

      expect(outcome).to respond_to(:skipped?)
      expect(outcome.skipped?).to be(true)
    end

    it "does not write a version for a stale row" do
      salary_import = create(:salary_import)
      before = version_count_for(existing)

      as_bulk_import(salary_import) do
        service.apply_imported_salary(
          employee,
          base_salary: 55_000, bonus: 0, allowance: 0, effective_date: Date.new(2025, 1, 1)
        )
      end

      expect(version_count_for(existing)).to eq(before)
    end

    # A future dated row is newer, so it is a create rather than a skip.
    it "creates a period dated in the future" do
      salary_import = create(:salary_import)

      as_bulk_import(salary_import) do
        service.apply_imported_salary(
          employee,
          base_salary: 65_000, bonus: 0, allowance: 0, effective_date: Date.new(2027, 1, 1)
        )
      end

      expect(records_for(employee).count).to eq(2)
    end
  end
end
