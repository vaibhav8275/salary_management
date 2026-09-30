require "rails_helper"

# FR-2.5 / LLD §7 and §9.2 — the audit history answers who changed what, when,
# and where the change came from, grouped by the salary record it happened to.
#
# LLD §9.2 says the audit API "exposes what the HR UI needs without leaking
# internal database structure", so these examples assert the fields a version
# must answer (LLD §7.1) and not a serialized PaperTrail version. The grouping
# is part of the contract: the UI shows one change log per salary record, so the
# endpoint has to say which record each version belongs to.
RSpec.describe "Salary audit history", type: :request do
  let(:employee) { create(:employee) }

  def edited_salary
    record = create(:salary_record, employee: employee, effective_date: Date.new(2026, 1, 1), base_salary: 50_000)
    as_hr_manager { record.update!(base_salary: 60_000) }
    record
  end

  # The response is one group per salary record, so most examples read through
  # this rather than asserting on the array directly.
  def groups
    api_data.index_by { |group| group["salary_record_id"] }
  end

  def versions_for(record)
    groups.fetch(record.id).fetch("versions")
  end

  describe "GET /api/v1/employees/:id/salary/audit" do
    it "returns the change history" do
      edited_salary

      get "/api/v1/employees/#{employee.id}/salary/audit"

      expect(response).to have_http_status(:ok)
      expect(api_data).to be_present
    end

    it "groups the changes under the salary record they belong to" do
      record = edited_salary

      get "/api/v1/employees/#{employee.id}/salary/audit"

      expect(api_data.map { |group| group["salary_record_id"] }).to include(record.id)
      expect(groups).to have_key(record.id)
    end

    # The two records of an employee with one record each are the case the
    # grouping exists for: one flat list would have made it ambiguous which
    # change belonged to which period.
    it "keeps each record's changes separate from the other's" do
      first = create(:salary_record, employee: employee, effective_date: Date.new(2025, 1, 1), base_salary: 40_000)
      second = edited_salary

      get "/api/v1/employees/#{employee.id}/salary/audit"

      expect(groups.keys).to contain_exactly(first.id, second.id)
      expect(versions_for(first).size).to eq(1)
      expect(versions_for(second).size).to eq(2)
    end

    # Every record is versioned from the moment it is created, so a record that
    # has only ever been added still reports a group — holding just the create.
    # The UI shows that as a log with a single "created" entry rather than no log.
    it "reports a record that was never updated as a single create" do
      untouched = create(:salary_record, employee: employee, effective_date: Date.new(2025, 1, 1))
      edited_salary

      get "/api/v1/employees/#{employee.id}/salary/audit"

      expect(versions_for(untouched).size).to eq(1)
      expect(versions_for(untouched).map { |row| row["event"] }).to eq([ "create" ])
    end

    # LLD §7.1 — who, when, which record, what changed, previous, new, source.
    it "answers who changed it" do
      record = edited_salary

      get "/api/v1/employees/#{employee.id}/salary/audit"

      expect(versions_for(record).map { |row| row["changed_by"] }).to include("HR Manager")
    end

    it "answers when it changed" do
      record = edited_salary

      get "/api/v1/employees/#{employee.id}/salary/audit"

      expect(versions_for(record).map { |row| row["changed_at"] }).to all(be_present)
    end

    it "answers the previous and the new value" do
      record = edited_salary

      get "/api/v1/employees/#{employee.id}/salary/audit"

      entry = versions_for(record).detect { |row| row["event"] == "update" }
      expect(entry["changes"]).to include("base_salary")
    end

    it "answers where the change came from" do
      record = edited_salary

      get "/api/v1/employees/#{employee.id}/salary/audit"

      expect(versions_for(record).map { |row| row["source"] }).to include("manual")
    end

    it "reports a bulk import as its own source" do
      salary_import = create(:salary_import)
      record = nil
      as_bulk_import(salary_import) do
        record = create(:salary_record, employee: employee, effective_date: Date.new(2026, 1, 1), base_salary: 60_000)
      end

      get "/api/v1/employees/#{employee.id}/salary/audit"

      expect(versions_for(record).map { |row| row["source"] }).to include("bulk_import")
    end

    it "keeps an import's changes under the record they updated" do
      salary_import = create(:salary_import)
      existing = create(:salary_record, employee: employee, effective_date: Date.new(2026, 1, 1), base_salary: 50_000)
      as_bulk_import(salary_import) { existing.update!(base_salary: 70_000) }

      get "/api/v1/employees/#{employee.id}/salary/audit"

      expect(versions_for(existing).map { |row| row["salary_import_id"] }).to include(salary_import.id)
    end

    it "orders the history from newest to oldest" do
      record = edited_salary

      get "/api/v1/employees/#{employee.id}/salary/audit"

      timestamps = versions_for(record).map { |row| Time.parse(row["changed_at"].to_s) }
      expect(timestamps).to eq(timestamps.sort.reverse)
    end

    it "orders the groups by their most recent change" do
      create(:salary_record, employee: employee, effective_date: Date.new(2026, 6, 1))
      record = edited_salary

      get "/api/v1/employees/#{employee.id}/salary/audit"

      newest = api_data.map { |group| group["versions"].map { |row| Time.parse(row["changed_at"].to_s) }.max }
      expect(newest).to eq(newest.sort.reverse)
      expect(api_data.first["salary_record_id"]).to eq(record.id)
    end

    it "returns 404 for an unknown employee" do
      get "/api/v1/employees/999999/salary/audit"

      expect(response).to have_http_status(:not_found)
    end

    # LLD §7 — the audit trail is a different view from the salary history, so it
    # does not return one row per period.
    it "is not the salary history" do
      record = edited_salary

      get "/api/v1/employees/#{employee.id}/salary/audit"

      expect(api_data.size).to eq(1)
      expect(versions_for(record).size).to eq(2)
    end

    it "returns nothing for an employee with no salary records" do
      get "/api/v1/employees/#{employee.id}/salary/audit"

      expect(response).to have_http_status(:ok)
      expect(api_data).to eq([])
    end

    it "does not include another employee's changes" do
      edited_salary
      other = create(:employee)
      as_hr_manager { create(:salary_record, employee: other, base_salary: 10_000).update!(base_salary: 20_000) }

      get "/api/v1/employees/#{employee.id}/salary/audit"

      record_ids = Employee.find(employee.id).salary_records.pluck(:id)
      expect(api_data.map { |group| group["salary_record_id"] }).to all(be_in(record_ids))
    end
  end
end
