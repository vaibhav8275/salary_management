require "rails_helper"

# LLD §9 — reverting restores the previous value through a *normal* salary
# update. The PaperTrail version is never deleted or rewritten: the revert is
# recorded as a new version, so the audit sequence keeps all three states.
RSpec.describe "Reverting a salary change", type: :service do
  let(:employee) { create(:employee) }
  let(:service) { SalaryService.new }

  def revert(version)
    service.revert_salary_change(version)
  end

  describe "the restored value" do
    it "puts the previous amount back" do
      record = create(:salary_record, employee: employee, base_salary: 50_000)
      as_hr_manager { record.update!(base_salary: 60_000) }

      revert(latest_version_for(record))

      expect(record.reload.base_salary).to eq(BigDecimal("50000.0"))
    end

    it "restores the bonus too" do
      record = create(:salary_record, employee: employee, base_salary: 50_000, bonus: 0)
      as_hr_manager { record.update!(bonus: 5_000) }

      revert(latest_version_for(record))

      expect(record.reload.bonus).to eq(BigDecimal("0"))
    end

    it "does not change the effective date" do
      record = create(:salary_record, employee: employee, effective_date: Date.new(2026, 1, 1), base_salary: 50_000)
      as_hr_manager { record.update!(base_salary: 60_000) }

      revert(latest_version_for(record))

      expect(record.reload.effective_date).to eq(Date.new(2026, 1, 1))
    end

    it "does not create or delete salary records" do
      record = create(:salary_record, employee: employee, base_salary: 50_000)
      as_hr_manager { record.update!(base_salary: 60_000) }
      before = SalaryRecord.count

      revert(latest_version_for(record))

      expect(SalaryRecord.count).to eq(before)
    end
  end

  # LLD §9 — the trail is preserved, not rewritten.
  describe "the audit trail" do
    it "adds a version for the revert" do
      record = create(:salary_record, employee: employee, base_salary: 50_000)
      as_hr_manager { record.update!(base_salary: 60_000) }
      before = version_count_for(record)

      revert(latest_version_for(record))

      expect(version_count_for(record)).to eq(before + 1)
    end

    it "keeps the incorrect value visible in the history" do
      record = create(:salary_record, employee: employee, base_salary: 50_000)
      as_hr_manager { record.update!(base_salary: 60_000) }
      revert(latest_version_for(record))

      amounts = version_amounts(record, "base_salary")

      expect(amounts).to include("60000.0", "50000.0")
    end

    it "records the revert as a manual change" do
      record = create(:salary_record, employee: employee, base_salary: 50_000)
      as_hr_manager { record.update!(base_salary: 60_000) }

      revert(latest_version_for(record))

      expect(latest_version_for(record).source).to eq("manual")
    end

    it "attributes the revert to the HR Manager" do
      record = create(:salary_record, employee: employee, base_salary: 50_000)
      as_hr_manager { record.update!(base_salary: 60_000) }

      revert(latest_version_for(record))

      expect(latest_version_for(record).whodunnit).to eq("HR Manager")
    end
  end

  describe "reverting a revert" do
    it "goes forward again" do
      record = create(:salary_record, employee: employee, base_salary: 50_000)
      as_hr_manager { record.update!(base_salary: 60_000) }
      revert(latest_version_for(record))

      revert(latest_version_for(record))

      expect(record.reload.base_salary).to eq(BigDecimal("60_000.0"))
    end

    it "keeps the whole sequence" do
      record = create(:salary_record, employee: employee, base_salary: 50_000)
      as_hr_manager { record.update!(base_salary: 60_000) }
      revert(latest_version_for(record))
      revert(latest_version_for(record))

      expect(version_amounts(record, "base_salary")).to include("50000.0", "60000.0")
    end
  end

  describe "edge cases" do
    # The create version has no previous state, so it cannot be reverted. How
    # that is signalled is a design decision, so these examples only assert that
    # nothing changes.
    it "changes nothing when asked to revert the create version" do
      record = create(:salary_record, employee: employee, base_salary: 50_000)
      create_version = versions_for(record).first
      before = version_count_for(record)

      revert(create_version)

      expect(record.reload.base_salary).to eq(BigDecimal("50000.0"))
      expect(version_count_for(record)).to eq(before)
    end

    it "does not remove the create version" do
      record = create(:salary_record, employee: employee, base_salary: 50_000)
      create_version = versions_for(record).first

      revert(create_version)

      expect(versions_for(record)).to include(create_version)
    end
  end
end
