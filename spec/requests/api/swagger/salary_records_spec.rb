require "swagger_helper"

RSpec.describe "Salary Records API", type: :request do
  # ── GET /api/v1/employees/:id/salary ────────────────────────────────────
  path "/api/v1/employees/{id}/salary" do
    parameter name: :id, in: :path, type: :integer, required: true,
              description: "Employee id"

    get "Current salary" do
      tags        "Salary"
      operationId "getCurrentSalary"
      produces    "application/json"
      description "Returns the most recent salary record with an effective date on or before today (LLD §5.1)."

      response "200", "current salary record (null when no record exists)" do
        schema type: :object,
               properties: {
                 data: {
                   oneOf: [
                     { "$ref" => "#/components/schemas/SalaryRecord" },
                     { type: :object, nullable: true }
                   ]
                 }
               },
               required: %w[data]

        let(:id) do
          emp = create(:employee)
          create(:salary_record, employee: emp)
          emp.id
        end
        run_test!
      end

      response "404", "employee not found" do
        schema "$ref" => "#/components/schemas/ErrorEnvelope"

        let(:id) { 999_999 }
        run_test!
      end
    end

    post "Create salary record" do
      tags        "Salary"
      operationId "createSalaryRecord"
      consumes    "application/x-www-form-urlencoded"
      produces    "application/json"
      description "Opens a new salary period. The effective date must be later than any existing period (LLD §5.2)."

      parameter name: :base_salary,    in: :formData, type: :number, required: true,
                description: "Base salary amount (BR-1: must be ≥ 0)"
      parameter name: :bonus,          in: :formData, type: :number, required: false,
                description: "Bonus (default 0)"
      parameter name: :allowance,      in: :formData, type: :number, required: false,
                description: "Allowance (default 0)"
      parameter name: :effective_date, in: :formData, type: :string, format: :date, required: true,
                description: "ISO-8601 date when this period begins"

      response "201", "salary record created" do
        schema type: :object,
               properties: {
                 data: { "$ref" => "#/components/schemas/SalaryRecord" }
               },
               required: %w[data]

        let(:id)             { create(:employee).id }
        let(:base_salary)    { 60_000 }
        let(:effective_date) { "2026-01-01" }
        run_test!
      end

      response "404", "employee not found" do
        schema "$ref" => "#/components/schemas/ErrorEnvelope"

        let(:id)             { 999_999 }
        let(:base_salary)    { 60_000 }
        let(:effective_date) { "2026-01-01" }
        run_test!
      end

      response "422", "invalid or missing parameters" do
        schema "$ref" => "#/components/schemas/ErrorEnvelope"

        let(:id)             { create(:employee).id }
        let(:base_salary)    { "not-a-number" }
        let(:effective_date) { "2026-01-01" }
        run_test!
      end
    end
  end

  # ── PATCH /api/v1/employees/:id/salary/:salary_record_id ────────────────
  path "/api/v1/employees/{id}/salary/{salary_record_id}" do
    parameter name: :id,               in: :path, type: :integer, required: true,
              description: "Employee id"
    parameter name: :salary_record_id, in: :path, type: :integer, required: true,
              description: "Salary record id to correct"

    patch "Correct a salary record" do
      tags        "Salary"
      operationId "updateSalaryRecord"
      consumes    "application/x-www-form-urlencoded"
      produces    "application/json"
      description "Corrects an existing salary period. Omitted fields keep their current value (LLD §5.3)."

      parameter name: :base_salary, in: :formData, type: :number, required: false,
                description: "New base salary"
      parameter name: :bonus,       in: :formData, type: :number, required: false,
                description: "New bonus"
      parameter name: :allowance,   in: :formData, type: :number, required: false,
                description: "New allowance"

      response "200", "salary record updated" do
        schema type: :object,
               properties: {
                 data: { "$ref" => "#/components/schemas/SalaryRecord" }
               },
               required: %w[data]

        let(:employee)         { create(:employee) }
        let(:record)           { create(:salary_record, employee: employee) }
        let(:id)               { employee.id }
        let(:salary_record_id) { record.id }
        let(:base_salary)      { 70_000 }
        run_test!
      end

      response "404", "employee or salary record not found" do
        schema "$ref" => "#/components/schemas/ErrorEnvelope"

        let(:id)               { create(:employee).id }
        let(:salary_record_id) { 999_999 }
        run_test!
      end
    end
  end

  # ── GET /api/v1/employees/:id/salary/history ────────────────────────────
  path "/api/v1/employees/{id}/salary/history" do
    parameter name: :id, in: :path, type: :integer, required: true,
              description: "Employee id"

    get "Salary history" do
      tags        "Salary"
      operationId "getSalaryHistory"
      produces    "application/json"
      description "All salary periods for the employee, newest first (FR-2.2)."

      response "200", "salary history" do
        schema type: :object,
               properties: {
                 data: {
                   type: :array,
                   items: { "$ref" => "#/components/schemas/SalaryRecord" }
                 }
               },
               required: %w[data]

        let(:id) do
          emp = create(:employee)
          create(:salary_record, employee: emp, effective_date: Date.new(2025, 1, 1))
          create(:salary_record, employee: emp, effective_date: Date.new(2026, 1, 1))
          emp.id
        end
        run_test!
      end

      response "404", "employee not found" do
        schema "$ref" => "#/components/schemas/ErrorEnvelope"

        let(:id) { 999_999 }
        run_test!
      end
    end
  end

  # ── GET /api/v1/employees/:id/salary/audit ──────────────────────────────
  path "/api/v1/employees/{id}/salary/audit" do
    parameter name: :id, in: :path, type: :integer, required: true,
              description: "Employee id"

    get "Salary audit trail" do
      tags        "Salary"
      operationId "getSalaryAudit"
      produces    "application/json"
      description "Full audit trail for all salary changes, newest first (FR-2.5, LLD §7.1)."

      response "200", "audit entries" do
        schema type: :object,
               properties: {
                 data: {
                   type: :array,
                   items: { "$ref" => "#/components/schemas/SalaryAudit" }
                 }
               },
               required: %w[data]

        let(:id) { create(:employee).id }
        run_test!
      end

      response "404", "employee not found" do
        schema "$ref" => "#/components/schemas/ErrorEnvelope"

        let(:id) { 999_999 }
        run_test!
      end
    end
  end

  # ── POST /api/v1/salary-records/:id/revert ──────────────────────────────
  path "/api/v1/salary-records/{id}/revert" do
    parameter name: :id, in: :path, type: :integer, required: true,
              description: "Salary record id"

    post "Revert last salary change" do
      tags        "Salary"
      operationId "revertSalaryRecord"
      produces    "application/json"
      description "Restores the salary record to its previous state (LLD §9)."

      response "200", "salary reverted" do
        schema type: :object,
               properties: {
                 data: { "$ref" => "#/components/schemas/SalaryRecord" }
               },
               required: %w[data]

        let(:id) do
          record = create(:salary_record, base_salary: 50_000)
          SalaryService.new.update_salary_record(record, base_salary: 60_000, bonus: 0, allowance: 0)
          record.id
        end
        run_test!
      end

      response "404", "salary record not found" do
        schema "$ref" => "#/components/schemas/ErrorEnvelope"

        let(:id) { 999_999 }
        run_test!
      end
    end
  end
end
