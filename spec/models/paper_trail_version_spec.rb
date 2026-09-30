require "rails_helper"

# LLD §7 — the audit trail answers "who changed what, when, and where the change
# came from". Every salary change writes a PaperTrail version; a re-apply with
# identical values writes nothing; provenance is recorded on the version and not
# on the salary record.
RSpec.describe "Salary record audit trail", type: :model do
  let(:employee) { create(:employee) }

  describe "creating a record" do
    it "writes a create version" do
      as_hr_manager { create(:salary_record, employee: employee) }

      version = versions_for(SalaryRecord.last).last

      expect(version.event).to eq("create")
    end

    it "attributes the change to the current user" do
      as_hr_manager { create(:salary_record, employee: employee) }

      expect(latest_version_for(SalaryRecord.last).whodunnit).to eq("HR Manager")
    end
  end

  describe "updating a record" do
    it "records an update event with the changed fields" do
      record = create(:salary_record, employee: employee, base_salary: 50_000)
      as_hr_manager { record.update!(base_salary: 55_000) }

      version = versions_for(record).last

      expect(version.event).to eq("update")
      expect(version.object_changes).to include("base_salary")
      expect(version.object["base_salary"]).not_to eq(version.object_changes["base_salary"])
    end

    it "stores the state before and after the change" do
      record = create(:salary_record, employee: employee, base_salary: 50_000)
      as_hr_manager { record.update!(base_salary: 55_000) }

      version = versions_for(record).last

      expect(BigDecimal(version.object["base_salary"])).to eq(BigDecimal("50000.0"))
      expect(BigDecimal(version.object_changes["base_salary"].last)).to eq(BigDecimal("55000.0"))
    end
  end

  # LLD §5.3 / BR-2 — re-applying identical values is a no-op and must not grow
  # the audit trail.
  describe "a no-op update" do
    it "writes no version" do
      record = create(:salary_record,
        employee: employee,
        base_salary: 50_000,
        bonus: 0,
        allowance: 0
      )
      before = version_count_for(record)

      as_hr_manager { record.update!(base_salary: 50_000, bonus: 0, allowance: 0) }

      expect(version_count_for(record)).to eq(before)
    end
  end

  describe "provenance" do
    it "defaults to the manual source" do
      as_hr_manager { create(:salary_record, employee: employee) }

      expect(latest_version_for(SalaryRecord.last).source).to eq("manual")
    end

    it "records bulk_import with the originating import id" do
      salary_import = create(:salary_import)
      as_bulk_import(salary_import) { create(:salary_record, employee: employee) }

      version = latest_version_for(SalaryRecord.last)

      expect(version.source).to eq("bulk_import")
      expect(version.salary_import_id).to eq(salary_import.id)
    end

    # LLD §7.3 — provenance lives on the version, not on SalaryRecord.
    it "does not add a salary_import_id column to salary records" do
      expect(SalaryRecord.column_names).not_to include("salary_import_id")
    end

    it "does not leak the actor into the next change" do
      as_hr_manager { create(:salary_record, employee: employee) }
      create(:salary_record, employee: create(:employee))

      expect(latest_version_for(SalaryRecord.last).whodunnit).to be_nil
    end
  end

  # LLD §7.4 — the trail is capped so it cannot grow without bound.
  describe "version limit" do
    # PaperTrail enforces `version_limit` against *update* versions only:
    # `PaperTrail::Version#enforce_version_limit!` prunes
    # `sibling_versions.not_creates`. The create version is never pruned, so the
    # configured limit of 50 yields 51 rows in total: the original create plus
    # the 50 most recent changes.
    it "keeps the create version plus at most 50 changes" do
      record = create(:salary_record, employee: employee, base_salary: 0)

      55.times { |i| record.update!(base_salary: i + 1) }

      expect(version_count_for(record)).to eq(51)
    end

    it "keeps the create version when the limit is exceeded" do
      record = create(:salary_record, employee: employee, base_salary: 0)
      55.times { |i| record.update!(base_salary: i + 1) }

      expect(versions_for(record).first.event).to eq("create")
    end

    it "keeps the most recent changes" do
      record = create(:salary_record, employee: employee, base_salary: 0)
      55.times { |i| record.update!(base_salary: i + 1) }

      recorded = latest_version_for(record).object_changes["base_salary"].last

      # JSON round trips the decimal as a string, so compare as decimals.
      expect(BigDecimal(recorded.to_s)).to eq(BigDecimal("55"))
    end
  end

  # LLD §7.5 — versions are stored as JSONB, so the previous state can be
  # rebuilt from a recorded object.
  describe "reifying a version" do
    it "restores the recorded object" do
      record = create(:salary_record, employee: employee, base_salary: 50_000)
      as_hr_manager { record.update!(base_salary: 55_000) }
      update_version = versions_for(record).last

      previous = update_version.reify(has_one: false)

      expect(previous.base_salary).to eq(BigDecimal("50000.0"))
    end

    it "has nothing to reify for the create version" do
      record = create(:salary_record, employee: employee, base_salary: 50_000)

      expect(versions_for(record).first.reify(has_one: false)).to be_nil
    end
  end
end
