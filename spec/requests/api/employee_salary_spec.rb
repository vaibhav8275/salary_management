require "rails_helper"

# FR-2.1 to FR-2.7 / LLD §5 and §9.1 — reading, creating and editing a
# salary for one employee.
#
# LLD §9.1 lists no create endpoint, but FR-2.3 requires entering a new salary
# period, so `POST /api/v1/employees/:id/salary` is the assumed route. Request
# parameters are assumed to be sent at the top level rather than nested under
# "salary"; both are assumptions LLD §9 leaves open.
RSpec.describe "Employee salary", type: :request do
  let(:employee) { create(:employee) }

  describe "GET /api/v1/employees/:id/salary" do
    it "returns the current salary" do
      create(:salary_record, employee: employee, effective_date: Date.new(2026, 1, 1), base_salary: 60_000)

      get "/api/v1/employees/#{employee.id}/salary"

      expect(response).to have_http_status(:ok)
      expect(BigDecimal(api_data["base_salary"].to_s)).to eq(BigDecimal("60000.0"))
    end

    it "returns the latest non-future period" do
      create(:salary_record, employee: employee, effective_date: Date.new(2024, 1, 1), base_salary: 50_000)
      create(:salary_record, employee: employee, effective_date: Date.new(2026, 1, 1), base_salary: 60_000)

      get "/api/v1/employees/#{employee.id}/salary"

      expect(api_data["effective_date"]).to eq("2026-01-01")
    end

    # LLD §5.1 — a future dated record must not become current prematurely.
    it "ignores a future dated record" do
      create(:salary_record, employee: employee, effective_date: Date.new(2026, 1, 1), base_salary: 60_000)
      create(:salary_record, employee: employee, effective_date: 1.year.from_now.to_date, base_salary: 70_000)

      get "/api/v1/employees/#{employee.id}/salary"

      expect(api_data["effective_date"]).to eq("2026-01-01")
    end

    it "returns the record effective today" do
      create(:salary_record, employee: employee, effective_date: Date.current, base_salary: 60_000)

      get "/api/v1/employees/#{employee.id}/salary"

      expect(BigDecimal(api_data["base_salary"].to_s)).to eq(BigDecimal("60000.0"))
    end

    it "returns a null salary for an employee with no records" do
      get "/api/v1/employees/#{employee.id}/salary"

      expect(response).to have_http_status(:ok)
      expect(api_data).to be_nil
    end

    it "returns 404 for an unknown employee" do
      get "/api/v1/employees/999999/salary"

      expect(response).to have_http_status(:not_found)
    end

    # BR-8 — the amount is always denominated in the employee's currency.
    it "names the currency" do
      create(:salary_record, employee: employee, base_salary: 60_000)

      get "/api/v1/employees/#{employee.id}/salary"

      expect(api_currency_code).to eq("USD")
    end
  end

  describe "POST /api/v1/employees/:id/salary" do
    # LLD §5.2 — a new effective period leaves earlier periods intact.
    it "creates the record" do
      post "/api/v1/employees/#{employee.id}/salary",
           params: { base_salary: "60000", bonus: "0", allowance: "0", effective_date: "2026-01-01" }

      expect(response).to have_http_status(:created)
      expect(SalaryRecord.where(employee_id: employee.id).count).to eq(1)
    end

    it "keeps the earlier period intact" do
      create(:salary_record, employee: employee, effective_date: Date.new(2025, 1, 1), base_salary: 50_000)

      post "/api/v1/employees/#{employee.id}/salary",
           params: { base_salary: "60000", bonus: "0", allowance: "0", effective_date: "2026-01-01" }

      expect(response).to have_http_status(:created)
      expect(SalaryRecord.where(employee_id: employee.id).count).to eq(2)
    end

    it "rejects a second record for the same period" do
      create(:salary_record, employee: employee, effective_date: Date.new(2026, 1, 1), base_salary: 60_000)

      post "/api/v1/employees/#{employee.id}/salary",
           params: { base_salary: "70000", bonus: "0", allowance: "0", effective_date: "2026-01-01" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(SalaryRecord.where(employee_id: employee.id).count).to eq(1)
    end

    it "returns an errors envelope for a negative amount" do
      post "/api/v1/employees/#{employee.id}/salary",
           params: { base_salary: "-1", bonus: "0", allowance: "0", effective_date: "2026-01-01" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(api_errors).to be_present
    end

    it "rejects a missing effective date" do
      post "/api/v1/employees/#{employee.id}/salary", params: { base_salary: "60000" }

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "rejects a non numeric amount" do
      post "/api/v1/employees/#{employee.id}/salary",
           params: { base_salary: "abc", effective_date: "2026-01-01" }

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 404 for an unknown employee" do
      post "/api/v1/employees/999999/salary",
           params: { base_salary: "60000", effective_date: "2026-01-01" }

      expect(response).to have_http_status(:not_found)
    end

    it "writes an audit version" do
      post "/api/v1/employees/#{employee.id}/salary",
           params: { base_salary: "60000", bonus: "0", allowance: "0", effective_date: "2026-01-01" }

      expect(PaperTrail::Version.where(item_type: "SalaryRecord").count).to eq(1)
    end
  end

  describe "PATCH /api/v1/employees/:id/salary/:salary_record_id" do
    let(:record) { create(:salary_record, employee: employee, effective_date: Date.new(2026, 1, 1), base_salary: 60_000) }

    # LLD §5.3 / FR-2.4 — an edit updates the same period.
    it "updates the record" do
      patch "/api/v1/employees/#{employee.id}/salary/#{record.id}", params: { base_salary: "62000" }

      expect(response).to have_http_status(:ok)
      expect(record.reload.base_salary).to eq(BigDecimal("62000.0"))
    end

    it "does not create a second record for the period" do
      patch "/api/v1/employees/#{employee.id}/salary/#{record.id}", params: { base_salary: "62000" }

      expect(SalaryRecord.where(employee_id: employee.id).count).to eq(1)
    end

    it "keeps the effective date unchanged" do
      patch "/api/v1/employees/#{employee.id}/salary/#{record.id}", params: { base_salary: "62000" }

      expect(record.reload.effective_date).to eq(Date.new(2026, 1, 1))
    end

    # LLD §5.3 — identical values are a no-op and write no version.
    it "writes no version for identical values" do
      before = version_count_for(record)

      patch "/api/v1/employees/#{employee.id}/salary/#{record.id}",
            params: { base_salary: "60000", bonus: "0", allowance: "0" }

      expect(version_count_for(record)).to eq(before)
    end

    it "writes a version when a value changes" do
      patch "/api/v1/employees/#{employee.id}/salary/#{record.id}", params: { base_salary: "62000" }

      expect(version_count_for(record)).to eq(2)
    end

    it "rejects a negative amount without changing the record" do
      patch "/api/v1/employees/#{employee.id}/salary/#{record.id}", params: { base_salary: "-1" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(record.reload.base_salary).to eq(BigDecimal("60000.0"))
    end

    # The effective date is what identifies a period, so an edit changes the
    # amounts only. A caller sending a date must not be able to reorder history.
    it "ignores an effective_date in the request" do
      original_date = record.effective_date

      patch "/api/v1/employees/#{employee.id}/salary/#{record.id}",
            params: { base_salary: "62000", effective_date: "2019-01-01" }

      expect(response).to have_http_status(:ok)
      expect(record.reload.effective_date).to eq(original_date)
      expect(record.reload.base_salary).to eq(BigDecimal("62000.0"))
    end

    it "returns 404 for an unknown record id" do
      patch "/api/v1/employees/#{employee.id}/salary/999999", params: { base_salary: "62000" }

      expect(response).to have_http_status(:not_found)
    end

    # A record id belonging to a different employee must not be editable through
    # this employee's URL.
    it "returns 404 for a record belonging to another employee" do
      other_record = create(:salary_record, employee: create(:employee), effective_date: Date.new(2026, 1, 1))

      patch "/api/v1/employees/#{employee.id}/salary/#{other_record.id}", params: { base_salary: "62000" }

      expect(response).to have_http_status(:not_found)
    end

    it "leaves the other employee's record untouched" do
      other = create(:employee)
      other_record = create(:salary_record, employee: other, effective_date: Date.new(2026, 1, 1), base_salary: 50_000)

      patch "/api/v1/employees/#{employee.id}/salary/#{other_record.id}", params: { base_salary: "62000" }

      expect(other_record.reload.base_salary).to eq(BigDecimal("50000.0"))
    end
  end
end
