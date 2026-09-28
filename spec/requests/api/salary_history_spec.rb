require "rails_helper"

# FR-2.2 / LLD §10.1 — the salary history is every period, oldest first, and it
# is a separate view from the audit history (LLD §7).
RSpec.describe "GET /api/v1/employees/:id/salary/history", type: :request do
  let(:employee) { create(:employee) }

  before do
    create(:salary_record, employee: employee, effective_date: Date.new(2024, 1, 1), base_salary: 50_000, bonus: 1_000, allowance: 100)
    create(:salary_record, employee: employee, effective_date: Date.new(2025, 1, 1), base_salary: 55_000)
    create(:salary_record, employee: employee, effective_date: Date.new(2026, 1, 1), base_salary: 60_000)
  end

  it "returns every period" do
    get "/api/v1/employees/#{employee.id}/salary/history"

    expect(response).to have_http_status(:ok)
    expect(api_data.size).to eq(3)
  end

  it "orders the periods from oldest to newest" do
    get "/api/v1/employees/#{employee.id}/salary/history"

    expect(api_data.map { |row| row["effective_date"] })
      .to eq(%w[2024-01-01 2025-01-01 2026-01-01])
  end

  it "includes every amount" do
    get "/api/v1/employees/#{employee.id}/salary/history"

    expect(api_data.first).to include("base_salary", "bonus", "allowance", "effective_date")
  end

  it "returns the amounts" do
    get "/api/v1/employees/#{employee.id}/salary/history"

    expect(BigDecimal(api_data.first["base_salary"].to_s)).to eq(BigDecimal("50000.0"))
  end

  it "returns an empty history for an employee with no salary" do
    get "/api/v1/employees/#{create(:employee).id}/salary/history"

    expect(response).to have_http_status(:ok)
    expect(api_data).to be_empty
  end

  it "returns 404 for an unknown employee" do
    get "/api/v1/employees/999999/salary/history"

    expect(response).to have_http_status(:not_found)
  end

  it "does not include another employee's periods" do
    other = create(:employee)
    create(:salary_record, employee: other, effective_date: Date.new(2023, 1, 1), base_salary: 42_000)

    get "/api/v1/employees/#{employee.id}/salary/history"

    expect(api_data.map { |row| BigDecimal(row["base_salary"].to_s) }).not_to include(BigDecimal("42000.0"))
  end

  it "exposes the record id needed to correct a period" do
    get "/api/v1/employees/#{employee.id}/salary/history"

    expect(api_data.map { |row| row["id"] }).to all(be_a(Integer))
  end

  # BR-8 — each period is denominated in the employee's own currency.
  it "names the currency" do
    get "/api/v1/employees/#{employee.id}/salary/history"

    expect(api_currency_code).to eq("USD")
  end
end
