require "swagger_helper"

RSpec.describe "Reports API", type: :request do
  COMMON_REPORT_PARAMS = [
    { name: :department, in: :query, type: :string,  required: false,
      description: "Filter by department name" },
    { name: :country,    in: :query, type: :string,  required: false,
      description: "Filter by country name" },
    { name: :from,       in: :query, type: :string,  format: :date, required: false,
      description: "Start of effective-date range (ISO-8601)" },
    { name: :to,         in: :query, type: :string,  format: :date, required: false,
      description: "End of effective-date range (ISO-8601)" }
  ].freeze

  # ── GET /api/v1/reports/average-salary-by-department ────────────────────
  path "/api/v1/reports/average-salary-by-department" do
    get "Average salary by department" do
      tags        "Reports"
      operationId "averageSalaryByDepartment"
      produces    "application/json"
      description <<~DESC
        Average base salary per department, split by currency (BR-8, FR-7.1).
        A department that spans two countries is reported as two rows — one per currency.
      DESC

      COMMON_REPORT_PARAMS.each { |p| parameter p }

      response "200", "report data" do
        schema type: :object,
               properties: {
                 data: {
                   type: :array,
                   items: { "$ref" => "#/components/schemas/ReportRow" }
                 }
               },
               required: %w[data]

        run_test!
      end
    end
  end

  # ── GET /api/v1/reports/total-payroll-by-country ─────────────────────────
  path "/api/v1/reports/total-payroll-by-country" do
    get "Total payroll by country" do
      tags        "Reports"
      operationId "totalPayrollByCountry"
      produces    "application/json"
      description <<~DESC
        Total compensation (base + bonus + allowance) per country (BR-3, FR-7.3).
        A country is paid in exactly one currency, so there is one row per country.
      DESC

      COMMON_REPORT_PARAMS.each { |p| parameter p }

      response "200", "report data" do
        schema type: :object,
               properties: {
                 data: {
                   type: :array,
                   items: { "$ref" => "#/components/schemas/ReportRow" }
                 }
               },
               required: %w[data]

        run_test!
      end
    end
  end

  # ── GET /api/v1/reports/employee-counts ─────────────────────────────────
  path "/api/v1/reports/employee-counts" do
    get "Employee counts" do
      tags        "Reports"
      operationId "employeeCounts"
      produces    "application/json"
      description "Head count grouped by department or country (FR-7.5). No salary record is required for an employee to be counted."

      parameter name: :group_by,   in: :query, type: :string, required: true,
                enum: %w[department country],
                description: "Dimension to group by"
      parameter name: :department, in: :query, type: :string, required: false,
                description: "Filter by department name"
      parameter name: :country,    in: :query, type: :string, required: false,
                description: "Filter by country name"

      response "200", "count data" do
        schema type: :object,
               properties: {
                 data: {
                   type: :array,
                   items: { "$ref" => "#/components/schemas/EmployeeCountRow" }
                 }
               },
               required: %w[data]

        let(:group_by) { "department" }
        run_test!
      end

      response "422", "unknown group_by value" do
        schema "$ref" => "#/components/schemas/ErrorEnvelope"

        let(:group_by) { "salary" }
        run_test!
      end
    end
  end

  # ── GET /api/v1/reports/salary-distribution ──────────────────────────────
  path "/api/v1/reports/salary-distribution" do
    get "Salary distribution" do
      tags        "Reports"
      operationId "salaryDistribution"
      produces    "application/json"
      description <<~DESC
        Number of salary records per band (FR-7.2).
        Bands: 0-25k, 25k-50k, 50k-75k, 75k-100k, 100k+.
      DESC

      COMMON_REPORT_PARAMS.each { |p| parameter p }

      response "200", "distribution data" do
        schema type: :object,
               properties: {
                 data: {
                   type: :array,
                   items: { "$ref" => "#/components/schemas/DistributionRow" }
                 }
               },
               required: %w[data]

        run_test!
      end
    end
  end

  # ── GET /api/v1/reports/salary-trends ────────────────────────────────────
  path "/api/v1/reports/salary-trends" do
    get "Salary trends" do
      tags        "Reports"
      operationId "salaryTrends"
      produces    "application/json"
      description "Average base salary per effective-date period, ordered ascending (FR-7.4)."

      COMMON_REPORT_PARAMS.each { |p| parameter p }

      response "200", "trend data" do
        schema type: :object,
               properties: {
                 data: {
                   type: :array,
                   items: { "$ref" => "#/components/schemas/TrendRow" }
                 }
               },
               required: %w[data]

        run_test!
      end
    end
  end
end
