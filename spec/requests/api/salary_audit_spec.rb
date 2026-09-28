require "rails_helper"

# FR-2.5, FR-2.6 / LLD §7 and §10.2 — the audit history answers who changed what,
# when, and where the change came from; and a change can be reverted from it.
#
# LLD §10.2 says the audit API "exposes what the HR UI needs without leaking
# internal database structure", so these examples assert the fields a version
# must answer (LLD §7.1) and not a serialized PaperTrail version.
RSpec.describe "Salary audit history and revert", type: :request do
  let(:employee) { create(:employee) }

  def corrected_salary
    record = create(:salary_record, employee: employee, effective_date: Date.new(2026, 1, 1), base_salary: 50_000)
    as_hr_manager { record.update!(base_salary: 60_000) }
    record
  end

  describe "GET /api/v1/employees/:id/salary/audit" do
    it "returns the change history" do
      corrected_salary

      get "/api/v1/employees/#{employee.id}/salary/audit"

      expect(response).to have_http_status(:ok)
      expect(api_data).to be_present
    end

    # LLD §7.1 — who, when, which record, what changed, previous, new, source.
    it "answers who changed it" do
      corrected_salary

      get "/api/v1/employees/#{employee.id}/salary/audit"

      expect(api_data.map { |row| row["changed_by"] }).to include("HR Manager")
    end

    it "answers when it changed" do
      corrected_salary

      get "/api/v1/employees/#{employee.id}/salary/audit"

      expect(api_data.map { |row| row["changed_at"] }).to all(be_present)
    end

    it "answers which salary record changed" do
      record = corrected_salary

      get "/api/v1/employees/#{employee.id}/salary/audit"

      expect(api_data.map { |row| row["salary_record_id"] }).to include(record.id)
    end

    it "answers the previous and the new value" do
      corrected_salary

      get "/api/v1/employees/#{employee.id}/salary/audit"

      entry = api_data.detect { |row| row["event"] == "update" }
      expect(entry["changes"]).to include("base_salary")
    end

    it "answers where the change came from" do
      corrected_salary

      get "/api/v1/employees/#{employee.id}/salary/audit"

      expect(api_data.map { |row| row["source"] }).to include("manual")
    end

    it "reports a bulk import as its own source" do
      salary_import = create(:salary_import)
      as_bulk_import(salary_import) do
        create(:salary_record, employee: employee, effective_date: Date.new(2026, 1, 1), base_salary: 60_000)
      end

      get "/api/v1/employees/#{employee.id}/salary/audit"

      expect(api_data.map { |row| row["source"] }).to include("bulk_import")
    end

    it "orders the history from newest to oldest" do
      corrected_salary

      get "/api/v1/employees/#{employee.id}/salary/audit"

      timestamps = api_data.map { |row| Time.parse(row["changed_at"].to_s) }
      expect(timestamps).to eq(timestamps.sort.reverse)
    end

    it "returns 404 for an unknown employee" do
      get "/api/v1/employees/999999/salary/audit"

      expect(response).to have_http_status(:not_found)
    end

    # LLD §7 — the audit trail is a different view from the salary history, so
    # it does not return one row per period.
    it "is not the salary history" do
      corrected_salary

      get "/api/v1/employees/#{employee.id}/salary/audit"

      expect(api_data.size).to eq(2)
    end
  end

  describe "POST /api/v1/salary-records/:id/revert" do
    # LLD §9 — the revert is a normal salary update, recorded as a new version.
    it "restores the previous amount" do
      record = corrected_salary

      post "/api/v1/salary-records/#{record.id}/revert"

      expect(response).to have_http_status(:ok)
      expect(record.reload.base_salary).to eq(BigDecimal("50000.0"))
    end

    it "adds a version instead of deleting one" do
      record = corrected_salary
      before = version_count_for(record)

      post "/api/v1/salary-records/#{record.id}/revert"

      expect(version_count_for(record)).to eq(before + 1)
    end

    it "keeps the incorrect value visible in the history" do
      record = corrected_salary

      post "/api/v1/salary-records/#{record.id}/revert"

      expect(version_amounts(record, "base_salary")).to include("60000.0", "50000.0")
    end

    it "does not change the effective date" do
      record = corrected_salary

      post "/api/v1/salary-records/#{record.id}/revert"

      expect(record.reload.effective_date).to eq(Date.new(2026, 1, 1))
    end

    it "records the revert as a manual change" do
      record = corrected_salary

      post "/api/v1/salary-records/#{record.id}/revert"

      expect(latest_version_for(record).source).to eq("manual")
    end

    it "returns 404 for an unknown record" do
      post "/api/v1/salary-records/999999/revert"

      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for an errors envelope on an unknown record" do
      post "/api/v1/salary-records/999999/revert"

      expect(api_errors).to be_present
    end
  end
end
