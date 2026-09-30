require "rails_helper"

# FR-7.1 to FR-7.5 / LLD §11 — reporting. Reports aggregate in the database, join
# to the employee to resolve the currency, and never combine currencies into one
# monetary figure (BR-8).
#
# LLD §11 names the reports but not their routes, and REQUIREMENTS §3.7 names the
# filters but not the parameter names, so the paths and the `from`/`to` parameter
# names are the assumed contract, matching the Cucumber steps.
RSpec.describe "Reports", type: :request do
  describe "GET /api/v1/reports/average-salary-by-department" do
    it "averages base salary per department" do
      create(:salary_record, employee: create(:employee, department: ReferenceData.department("Engineering")), base_salary: 50_000)
      create(:salary_record, employee: create(:employee, department: ReferenceData.department("Engineering")), base_salary: 70_000)

      get "/api/v1/reports/average-salary-by-department"

      expect(response).to have_http_status(:ok)
      expect(BigDecimal(api_data.first["amount"].to_s)).to eq(BigDecimal("60000.0"))
    end

    it "names the department" do
      create(:salary_record, employee: create(:employee, department: ReferenceData.department("Engineering")), base_salary: 50_000)

      get "/api/v1/reports/average-salary-by-department"

      expect(api_data.first["department"]).to eq("Engineering")
    end

    # BR-8 — the currency is explicit on every monetary row.
    it "names the currency" do
      create(:salary_record, employee: create(:employee, :eur), base_salary: 50_000)

      get "/api/v1/reports/average-salary-by-department"

      expect(api_data.first["currency"]).to eq("EUR")
    end

    # BR-8 — a department spanning two currencies is reported per currency rather
    # than as one meaningless average.
    it "reports a department spanning two currencies twice" do
      create(:salary_record, employee: create(:employee, department: ReferenceData.department("Engineering")), base_salary: 50_000)
      create(:salary_record, employee: create(:employee, :eur, department: ReferenceData.department("Engineering")), base_salary: 40_000)

      get "/api/v1/reports/average-salary-by-department"

      expect(api_data.size).to eq(2)
      expect(api_data.map { |row| row["currency"] }).to contain_exactly("USD", "EUR")
    end

    it "filters by department" do
      create(:salary_record, employee: create(:employee, department: ReferenceData.department("Engineering")), base_salary: 50_000)
      create(:salary_record, employee: create(:employee, department: ReferenceData.department("Sales")), base_salary: 40_000)

      get "/api/v1/reports/average-salary-by-department", params: { department: "Sales" }

      expect(api_data.map { |row| row["department"] }).to eq([ "Sales" ])
    end

    it "filters by country" do
      create(:salary_record, employee: create(:employee, country: ReferenceData.country("United Kingdom")), base_salary: 50_000)
      create(:salary_record, employee: create(:employee, country: ReferenceData.country("Nigeria")), base_salary: 40_000)

      get "/api/v1/reports/average-salary-by-department", params: { country: "United Kingdom" }

      expect(api_data.size).to eq(1)
    end

    it "restricts to a date range" do
      employee = create(:employee)
      create(:salary_record, employee: employee, effective_date: Date.new(2025, 1, 1), base_salary: 50_000)
      create(:salary_record, employee: employee, effective_date: Date.new(2026, 1, 1), base_salary: 60_000)

      get "/api/v1/reports/average-salary-by-department",
          params: { from: "2026-01-01", to: "2026-12-31" }

      expect(BigDecimal(api_data.first["amount"].to_s)).to eq(BigDecimal("60000.0"))
    end

    it "returns an empty result when nothing matches" do
      get "/api/v1/reports/average-salary-by-department"

      expect(response).to have_http_status(:ok)
      expect(api_data).to be_empty
    end
  end

  describe "GET /api/v1/reports/total-payroll-by-country" do
    # BR-3 — total compensation includes bonus and allowance.
    it "sums base salary, bonus and allowance" do
      create(:salary_record,
        employee: create(:employee, country: ReferenceData.country("United Kingdom")),
        base_salary: 50_000, bonus: 1_000, allowance: 500
      )

      get "/api/v1/reports/total-payroll-by-country"

      expect(BigDecimal(api_data.first["amount"].to_s)).to eq(BigDecimal("51500.0"))
    end

    it "names the country and the currency" do
      create(:salary_record, employee: create(:employee, country: ReferenceData.country("United Kingdom")), base_salary: 40_000)

      get "/api/v1/reports/total-payroll-by-country"

      expect(api_data.first).to include("country" => "United Kingdom", "currency" => "GBP")
    end

    # LLD §2.3, §2.7 — a country is paid in exactly one currency, so employees in
    # one country are never a per-currency split. The split that can still happen
    # is a department spanning two countries, covered above.
    it "reports one row per country" do
      create(:salary_record, employee: create(:employee, country: ReferenceData.country("Nigeria")), base_salary: 40_000)
      create(:salary_record, employee: create(:employee, country: ReferenceData.country("Nigeria")), base_salary: 30_000)

      get "/api/v1/reports/total-payroll-by-country"

      expect(api_data.size).to eq(1)
      expect(api_data.first["amount"].to_s).to eq("70000.0")
    end

    it "sums every employee in a country" do
      create(:salary_record, employee: create(:employee, country: ReferenceData.country("Nigeria")), base_salary: 40_000)
      create(:salary_record, employee: create(:employee, country: ReferenceData.country("Nigeria")), base_salary: 30_000)

      get "/api/v1/reports/total-payroll-by-country"

      expect(BigDecimal(api_data.first["amount"].to_s)).to eq(BigDecimal("70000.0"))
    end

    # FR-7.3 — a date range, so the figure reflects the periods in range.
    it "restricts to a date range" do
      employee = create(:employee, country: ReferenceData.country("Nigeria"))
      create(:salary_record, employee: employee, effective_date: Date.new(2025, 1, 1), base_salary: 40_000)
      create(:salary_record, employee: employee, effective_date: Date.new(2026, 1, 1), base_salary: 60_000)

      get "/api/v1/reports/total-payroll-by-country",
          params: { from: "2026-01-01", to: "2026-12-31" }

      expect(BigDecimal(api_data.first["amount"].to_s)).to eq(BigDecimal("60000.0"))
    end

    it "returns an empty result when nothing matches" do
      get "/api/v1/reports/total-payroll-by-country"

      expect(response).to have_http_status(:ok)
      expect(api_data).to be_empty
    end
  end

  describe "GET /api/v1/reports/employee-counts" do
    it "counts by department" do
      3.times { create(:employee, department: ReferenceData.department("Engineering")) }
      create(:employee, department: ReferenceData.department("Sales"))

      get "/api/v1/reports/employee-counts", params: { group_by: "department" }

      counts = api_data.to_h { |row| [ row["department"], row["count"] ] }
      expect(counts).to eq("Engineering" => 3, "Sales" => 1)
    end

    it "counts by country" do
      2.times { create(:employee, country: ReferenceData.country("Nigeria")) }

      get "/api/v1/reports/employee-counts", params: { group_by: "country" }

      expect(api_data.to_h { |row| [ row["country"], row["count"] ] }).to eq("Nigeria" => 2)
    end

    # Employee counts are not monetary, so no currency is attached.
    it "carries no currency" do
      create(:employee)

      get "/api/v1/reports/employee-counts", params: { group_by: "department" }

      expect(api_data.first).not_to have_key("currency")
    end

    it "counts employees who have no salary" do
      create(:employee, department: ReferenceData.department("Engineering"))

      get "/api/v1/reports/employee-counts", params: { group_by: "department" }

      expect(api_data.first["count"]).to eq(1)
    end

    it "filters the department count by one department" do
      3.times { create(:employee, department: ReferenceData.department("Engineering")) }
      create(:employee, department: ReferenceData.department("Sales"))

      get "/api/v1/reports/employee-counts", params: { group_by: "department", department: "Sales" }

      expect(api_data.map { |row| row["count"] }).to eq([ 1 ])
    end

    it "filters the count by country" do
      3.times { create(:employee, country: ReferenceData.country("Nigeria")) }
      create(:employee, country: ReferenceData.country("United Kingdom"))

      get "/api/v1/reports/employee-counts", params: { group_by: "country", country: "Nigeria" }

      expect(api_data.map { |row| row["count"] }).to eq([ 3 ])
    end

    it "counts by job title" do
      2.times { create(:employee, job_title: ReferenceData.job_title("Software Engineer")) }
      create(:employee, job_title: ReferenceData.job_title("Accountant"))

      get "/api/v1/reports/employee-counts", params: { group_by: "job_title" }

      counts = api_data.to_h { |row| [ row["job_title"], row["count"] ] }
      expect(counts).to eq("Accountant" => 1, "Software Engineer" => 2)
    end

    it "filters the job title count by one job title" do
      3.times { create(:employee, job_title: ReferenceData.job_title("Software Engineer")) }
      create(:employee, job_title: ReferenceData.job_title("Accountant"))

      get "/api/v1/reports/employee-counts",
          params: { group_by: "job_title", job_title: "Accountant" }

      expect(api_data).to eq([ { "job_title" => "Accountant", "count" => 1 } ])
    end

    # A filter on a table the grouping did not join used to raise a missing
    # FROM-clause error, so the filters are exercised across groupings.
    it "applies a department filter to a country grouping" do
      create(:employee, department: ReferenceData.department("Sales"),
                         country: ReferenceData.country("Nigeria"))
      create(:employee, department: ReferenceData.department("Engineering"),
                         country: ReferenceData.country("Nigeria"))

      get "/api/v1/reports/employee-counts",
          params: { group_by: "country", department: "Sales" }

      expect(api_data).to eq([ { "country" => "Nigeria", "count" => 1 } ])
    end

    it "applies a job title filter to a department grouping" do
      create(:employee, department: ReferenceData.department("Sales"),
                         job_title: ReferenceData.job_title("Accountant"))
      create(:employee, department: ReferenceData.department("Sales"),
                         job_title: ReferenceData.job_title("Software Engineer"))

      get "/api/v1/reports/employee-counts",
          params: { group_by: "department", job_title: "Accountant" }

      expect(api_data).to eq([ { "department" => "Sales", "count" => 1 } ])
    end

    it "rejects an unknown grouping" do
      get "/api/v1/reports/employee-counts", params: { group_by: "salary" }

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "GET /api/v1/reports/salary-distribution" do
    # The LLD does not define the bands, so these examples only pin the shape
    # and the totals.
    it "returns bands with a count" do
      create(:salary_record, employee: create(:employee), base_salary: 30_000)
      create(:salary_record, employee: create(:employee), base_salary: 70_000)

      get "/api/v1/reports/salary-distribution"

      expect(api_data).to all(include("count"))
      expect(api_data.sum { |row| row["count"] }).to eq(2)
    end

    it "filters by department" do
      create(:salary_record, employee: create(:employee, department: ReferenceData.department("Engineering")), base_salary: 30_000)
      create(:salary_record, employee: create(:employee, department: ReferenceData.department("Sales")), base_salary: 70_000)

      get "/api/v1/reports/salary-distribution", params: { department: "Sales" }

      expect(api_data.sum { |row| row["count"] }).to eq(1)
    end

    it "filters by country" do
      create(:salary_record, employee: create(:employee, country: ReferenceData.country("United Kingdom")), base_salary: 30_000)
      create(:salary_record, employee: create(:employee, country: ReferenceData.country("Nigeria")), base_salary: 70_000)

      get "/api/v1/reports/salary-distribution", params: { country: "Nigeria" }

      expect(api_data.sum { |row| row["count"] }).to eq(1)
    end

    it "restricts to a date range" do
      employee = create(:employee)
      create(:salary_record, employee: employee, effective_date: Date.new(2025, 1, 1), base_salary: 30_000)
      create(:salary_record, employee: employee, effective_date: Date.new(2026, 1, 1), base_salary: 70_000)

      get "/api/v1/reports/salary-distribution",
          params: { from: "2026-01-01", to: "2026-12-31" }

      expect(api_data.sum { |row| row["count"] }).to eq(1)
    end

    it "returns an empty result with no salaries" do
      create(:employee)

      get "/api/v1/reports/salary-distribution"

      expect(api_data).to be_empty
    end
  end

  describe "GET /api/v1/reports/salary-trends" do
    it "reports an average per period" do
      employee = create(:employee)
      create(:salary_record, employee: employee, effective_date: Date.new(2025, 1, 1), base_salary: 50_000)
      create(:salary_record, employee: employee, effective_date: Date.new(2026, 1, 1), base_salary: 60_000)

      get "/api/v1/reports/salary-trends"

      expect(api_data.map { |row| row["effective_date"] }).to eq(%w[2025-01-01 2026-01-01])
    end

    it "reports the average rather than the sum for a period" do
      employee = create(:employee)
      create(:salary_record, employee: employee, effective_date: Date.new(2026, 1, 1), base_salary: 50_000)
      create(:salary_record, employee: create(:employee), effective_date: Date.new(2026, 1, 1), base_salary: 70_000)

      get "/api/v1/reports/salary-trends"

      expect(BigDecimal(api_data.first["amount"].to_s)).to eq(BigDecimal("60000.0"))
    end

    # FR-7.4 — a date range is the documented filter for trends.
    it "restricts to a date range" do
      employee = create(:employee)
      create(:salary_record, employee: employee, effective_date: Date.new(2025, 1, 1), base_salary: 50_000)
      create(:salary_record, employee: employee, effective_date: Date.new(2026, 1, 1), base_salary: 60_000)

      get "/api/v1/reports/salary-trends", params: { from: "2026-01-01", to: "2026-12-31" }

      expect(api_data.map { |row| row["effective_date"] }).to eq(%w[2026-01-01])
    end

    it "returns an empty result with no salaries" do
      get "/api/v1/reports/salary-trends"

      expect(api_data).to be_empty
    end
  end
end
