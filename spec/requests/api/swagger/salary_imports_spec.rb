require "swagger_helper"

RSpec.describe "Salary Imports API", type: :request do
  # ── POST /api/v1/salary-imports ──────────────────────────────────────────
  path "/api/v1/salary-imports" do
    post "Upload a salary CSV" do
      tags        "Salary Imports"
      operationId "createSalaryImport"
      consumes    "multipart/form-data"
      produces    "application/json"
      description <<~DESC
        Uploads a CSV file to S3, persists a SalaryImport record and enqueues
        the processing job. The file is never processed synchronously (FR-4.6).
        The S3 object key is never returned (LLD §10.3).
      DESC

      parameter name: :file, in: :formData, type: :file, required: true,
                description: "CSV file containing salary rows"

      response "201", "import accepted and queued" do
        schema type: :object,
               properties: {
                 data: { "$ref" => "#/components/schemas/SalaryImport" }
               },
               required: %w[data]

        let(:file) do
          Rack::Test::UploadedFile.new(
            StringIO.new("employee_id,base_salary,effective_date\n1,50000,2026-01-01"),
            "text/csv",
            original_filename: "salaries.csv"
          )
        end
        run_test!
      end

      response "422", "no file or wrong file type" do
        schema "$ref" => "#/components/schemas/ErrorEnvelope"

        let(:file) { nil }
        run_test!
      end
    end

    get "List salary imports" do
      tags        "Salary Imports"
      operationId "listSalaryImports"
      produces    "application/json"

      response "200", "list of imports (newest first)" do
        schema type: :object,
               properties: {
                 data: {
                   type: :array,
                   items: { "$ref" => "#/components/schemas/SalaryImport" }
                 }
               },
               required: %w[data]

        run_test!
      end
    end
  end

  # ── GET /api/v1/salary-imports/:id ───────────────────────────────────────
  path "/api/v1/salary-imports/{id}" do
    parameter name: :id, in: :path, type: :integer, required: true,
              description: "SalaryImport id"

    get "Retrieve a salary import" do
      tags        "Salary Imports"
      operationId "getSalaryImport"
      produces    "application/json"

      response "200", "import found" do
        schema type: :object,
               properties: {
                 data: { "$ref" => "#/components/schemas/SalaryImport" }
               },
               required: %w[data]

        let(:id) { create(:salary_import).id }
        run_test!
      end

      response "404", "import not found" do
        schema "$ref" => "#/components/schemas/ErrorEnvelope"

        let(:id) { 999_999 }
        run_test!
      end
    end
  end
end
