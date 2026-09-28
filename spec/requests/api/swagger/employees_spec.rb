require "swagger_helper"

RSpec.describe "Employees API", type: :request do
  # ── GET /api/v1/employees ────────────────────────────────────────────────
  path "/api/v1/employees" do
    get "List employees" do
      tags        "Employees"
      operationId "listEmployees"
      produces    "application/json"

      parameter name: :search,     in: :query, type: :string,  required: false,
                description: "Filter by name (first, last, full), email or id (FR-1.3)"
      parameter name: :department, in: :query, type: :string,  required: false,
                description: "Filter by exact department name"
      parameter name: :country,    in: :query, type: :string,  required: false,
                description: "Filter by exact country name"
      parameter name: :page,       in: :query, type: :integer, required: false,
                description: "Page number (default: 1)"
      parameter name: :per_page,   in: :query, type: :integer, required: false,
                description: "Page size (default: 25)"

      response "200", "employees returned" do
        schema type: :object,
               properties: {
                 data: {
                   type: :array,
                   items: { "$ref" => "#/components/schemas/Employee" }
                 },
                 meta: { "$ref" => "#/components/schemas/PaginationMeta" }
               },
               required: %w[data meta]

        let(:_setup) { create(:employee, first_name: "Ada", last_name: "Lovelace") }
        run_test!
      end
    end
  end

  # ── GET /api/v1/employees/:id ─────────────────────────────────────────────
  path "/api/v1/employees/{id}" do
    parameter name: :id, in: :path, type: :integer, required: true,
              description: "Employee id"

    get "Retrieve an employee" do
      tags        "Employees"
      operationId "getEmployee"
      produces    "application/json"

      response "200", "employee found" do
        schema type: :object,
               properties: {
                 data: { "$ref" => "#/components/schemas/EmployeeDetail" }
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
end
