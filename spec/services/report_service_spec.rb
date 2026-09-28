require "rails_helper"

# LLD §11 — reporting uses database level aggregation, joins to the employee to
# resolve the currency, and never mixes currencies into one monetary figure
# (BR-8). Reports degrade to an empty result rather than an error when nothing
# matches.
#
# `ReportService` is the assumed name; it is described by string so the missing
# constant does not break suite loading.
RSpec.describe "ReportService", type: :service do
  let(:service) { ReportService.new }

  describe "average salary by department (FR-7.1)" do
    it "averages base salary per department" do
      create(:salary_record, employee: create(:employee, department: ReferenceData.department("Engineering")), base_salary: 50_000)
      create(:salary_record, employee: create(:employee, department: ReferenceData.department("Engineering")), base_salary: 70_000)

      expect(service.average_salary_by_department).to eq([ { department: "Engineering", currency: "USD", amount: BigDecimal("60000.0") } ])
    end

    it "ignores employees with no salary record" do
      create(:employee, department: ReferenceData.department("Engineering"))

      expect(service.average_salary_by_department).to be_empty
    end

    it "reports each department separately" do
      create(:salary_record, employee: create(:employee, department: ReferenceData.department("Engineering")), base_salary: 50_000)
      create(:salary_record, employee: create(:employee, department: ReferenceData.department("Sales")), base_salary: 40_000)

      amounts = service.average_salary_by_department.to_h { |row| [ row[:department], row[:amount] ] }

      expect(amounts).to eq("Engineering" => BigDecimal("50000.0"), "Sales" => BigDecimal("40000.0"))
    end

    # BR-8 — a department spanning two currencies is reported per currency.
    it "splits a department by currency" do
      create(:salary_record, employee: create(:employee, department: ReferenceData.department("Engineering")), base_salary: 50_000)
      create(:salary_record, employee: create(:employee, :eur, department: ReferenceData.department("Engineering")), base_salary: 40_000)

      rows = service.average_salary_by_department

      expect(rows.size).to eq(2)
      expect(rows.map { |row| row[:currency] }).to contain_exactly("USD", "EUR")
    end

    it "filters to one department" do
      create(:salary_record, employee: create(:employee, department: ReferenceData.department("Engineering")), base_salary: 50_000)
      create(:salary_record, employee: create(:employee, department: ReferenceData.department("Sales")), base_salary: 40_000)

      expect(service.average_salary_by_department(department: "Sales").map { |row| row[:department] }).to eq([ "Sales" ])
    end

    it "filters to one country" do
      create(:salary_record, employee: create(:employee, country: ReferenceData.country("United Kingdom")), base_salary: 50_000)
      create(:salary_record, employee: create(:employee, country: ReferenceData.country("Nigeria")), base_salary: 40_000)

      expect(service.average_salary_by_department(country: "United Kingdom").map { |row| row[:amount] })
        .to eq([ BigDecimal("50000.0") ])
    end
  end

  describe "total payroll by country (FR-7.3)" do
    # BR-3 — total compensation is base + bonus + allowance.
    it "sums base salary, bonus and allowance" do
      create(:salary_record,
        employee: create(:employee, country: ReferenceData.country("United Kingdom")),
        base_salary: 50_000, bonus: 1_000, allowance: 500
      )

      expect(service.total_payroll_by_country).to eq(
        [ { country: "United Kingdom", currency: "GBP", amount: BigDecimal("51500.0") } ]
      )
    end

    # LLD §2.3, §2.8 — a country is paid in exactly one currency, so the payroll
    # of a country is one row: there is no per-currency split to make.
    it "reports one row per country" do
      create(:salary_record, employee: create(:employee, country: ReferenceData.country("United Kingdom")), base_salary: 50_000)
      create(:salary_record, employee: create(:employee, country: ReferenceData.country("United Kingdom")), base_salary: 30_000)

      rows = service.total_payroll_by_country

      expect(rows.size).to eq(1)
      expect(rows.first[:currency]).to eq("GBP")
    end

    it "sums several employees in the same country and currency" do
      create(:salary_record, employee: create(:employee, country: ReferenceData.country("United Kingdom")), base_salary: 50_000)
      create(:salary_record, employee: create(:employee, country: ReferenceData.country("United Kingdom")), base_salary: 30_000)

      expect(service.total_payroll_by_country.first[:amount]).to eq(BigDecimal("80000.0"))
    end
  end

  describe "employee count (FR-7.5)" do
    it "counts by department" do
      3.times { create(:employee, department: ReferenceData.department("Engineering")) }
      create(:employee, department: ReferenceData.department("Sales"))

      expect(service.employee_count_by_department).to eq(
        [ { department: "Engineering", count: 3 }, { department: "Sales", count: 1 } ]
      )
    end

    it "counts by country" do
      2.times { create(:employee, country: ReferenceData.country("United Kingdom")) }

      expect(service.employee_count_by_country).to eq([ { country: "United Kingdom", count: 2 } ])
    end

    it "counts every employee even without a salary" do
      create(:employee, department: ReferenceData.department("Engineering"))

      expect(service.employee_count_by_department).to eq([ { department: "Engineering", count: 1 } ])
    end

    it "filters the department count by one department" do
      3.times { create(:employee, department: ReferenceData.department("Engineering")) }
      create(:employee, department: ReferenceData.department("Sales"))

      expect(service.employee_count_by_department(department: "Sales")).to eq([ { department: "Sales", count: 1 } ])
    end
  end

  describe "salary distribution (FR-7.2)" do
    # The LLD does not define the buckets, so these examples assume simple
    # thresholds and flag them as an assumption to confirm.
    it "groups salaries into bands with a count" do
      create(:salary_record, employee: create(:employee), base_salary: 30_000)
      create(:salary_record, employee: create(:employee), base_salary: 45_000)
      create(:salary_record, employee: create(:employee), base_salary: 70_000)

      expect(service.salary_distribution.map { |row| row[:count] }.sum).to eq(3)
    end

    it "reports a count per band" do
      create(:salary_record, employee: create(:employee), base_salary: 30_000)
      create(:salary_record, employee: create(:employee), base_salary: 45_000)

      expect(service.salary_distribution).to all(include(:range, :count))
    end

    it "filters to one department" do
      create(:salary_record, employee: create(:employee, department: ReferenceData.department("Engineering")), base_salary: 30_000)
      create(:salary_record, employee: create(:employee, department: ReferenceData.department("Sales")), base_salary: 45_000)

      expect(service.salary_distribution(department: "Sales").map { |row| row[:count] }.sum).to eq(1)
    end

    it "returns an empty result when there are no salaries" do
      create(:employee)

      expect(service.salary_distribution).to be_empty
    end
  end

  describe "salary trends (FR-7.4)" do
    it "reports an average per effective period" do
      employee = create(:employee)
      create(:salary_record, employee: employee, effective_date: Date.new(2025, 1, 1), base_salary: 50_000)
      create(:salary_record, employee: employee, effective_date: Date.new(2026, 1, 1), base_salary: 60_000)

      expect(service.salary_trends.map { |row| row[:effective_date] })
        .to eq([ Date.new(2025, 1, 1), Date.new(2026, 1, 1) ])
    end

    it "averages employees sharing a period" do
      create(:salary_record, employee: create(:employee), effective_date: Date.new(2026, 1, 1), base_salary: 50_000)
      create(:salary_record, employee: create(:employee), effective_date: Date.new(2026, 1, 1), base_salary: 70_000)

      expect(service.salary_trends.first[:amount]).to eq(BigDecimal("60000.0"))
    end

    it "filters to one department" do
      create(:salary_record, employee: create(:employee, department: ReferenceData.department("Engineering")), effective_date: Date.new(2026, 1, 1))
      create(:salary_record, employee: create(:employee, department: ReferenceData.department("Sales")), effective_date: Date.new(2026, 1, 1))

      expect(service.salary_trends(department: "Sales").map { |row| row[:amount] })
        .to eq([ BigDecimal("50000.0") ])
    end

    it "restricts to a date range" do
      create(:salary_record, employee: create(:employee), effective_date: Date.new(2025, 1, 1), base_salary: 50_000)
      create(:salary_record, employee: create(:employee), effective_date: Date.new(2026, 1, 1), base_salary: 60_000)

      expect(service.salary_trends(from: Date.new(2026, 1, 1)).map { |row| row[:effective_date] })
        .to eq([ Date.new(2026, 1, 1) ])
    end
  end

  describe "empty results" do
    # LLD §11 — a report with no matching data is empty, not an error.
    it "returns nothing for average salary with no data" do
      expect(service.average_salary_by_department).to eq([])
    end

    it "returns nothing for total payroll with no data" do
      expect(service.total_payroll_by_country).to eq([])
    end

    it "returns nothing for trends with no data" do
      expect(service.salary_trends).to eq([])
    end
  end
end
