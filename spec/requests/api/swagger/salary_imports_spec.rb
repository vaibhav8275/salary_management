require "swagger_helper"

# The import example below uploads a CSV, which lands on the test disk service
# (config/storage.yml), so it needs no S3 credentials to document its response.
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
        The S3 object key is never returned (LLD §9.3).
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

  # ── GET /api/v1/salary-imports/:id/errors ────────────────────────────────
  path "/api/v1/salary-imports/{id}/errors" do
    parameter name: :id, in: :path, type: :integer, required: true,
              description: "SalaryImport id"

    get "List the failed rows of a salary import" do
      tags        "Salary Imports"
      operationId "listSalaryImportErrors"
      produces    "application/json"

      description <<~DESC
        The rows behind `failed_records`: row_number, employee_id, error_message
        and the raw_data exactly as it arrived in the file. Paginated 50 rows to a
        page, because an import over the full employee set can reject most of its
        rows.

        `summary` is a roll-up of these same rows grouped by reason, returned
        alongside the page so the two cannot disagree for an import that is still
        running. A whole-file failure appears here as a single row with
        row_number 0 and no employee_id.
      DESC

      parameter name: :page, in: :query, type: :integer, required: false, default: 1,
                description: "1-based page number. A missing or invalid value is treated as 1."

      response "200", "page of failed rows, with counts by reason" do
        schema type: :object,
               properties: {
                 data: {
                   type: :array,
                   items: { "$ref" => "#/components/schemas/SalaryImportError" }
                 },
                 meta: {
                   type: :object,
                   properties: {
                     current_page: { type: :integer, example: 1 },
                     per_page:     { type: :integer, example: 50 },
                     total_count:  { type: :integer, example: 60 },
                     total_pages:  { type: :integer, example: 2 }
                   },
                   required: %w[current_page per_page total_count total_pages]
                 },
                 summary: {
                   type: :array,
                   items: { "$ref" => "#/components/schemas/SalaryImportErrorSummaryRow" }
                 }
               },
               required: %w[data meta summary]

        let(:id) do
          salary_import = create(:salary_import, :completed_with_errors)
          create(:salary_import_error,
                 salary_import: salary_import,
                 row_number: 4,
                 error_message: "Invalid base_salary 'abc'",
                 raw_data: { "employee_id" => "7", "base_salary" => "abc" })
          salary_import.id
        end
        run_test!
      end

      response "404", "import not found" do
        schema "$ref" => "#/components/schemas/ErrorEnvelope"

        let(:id) { 999_999 }
        run_test!
      end
    end
  end

  # ── GET /api/v1/salary-imports/:id/csv ───────────────────────────────────
  path "/api/v1/salary-imports/{id}/csv" do
    parameter name: :id, in: :path, type: :integer, required: true,
              description: "SalaryImport id"

    get "Download the uploaded CSV" do
      tags        "Salary Imports"
      operationId "downloadSalaryImportCsv"

      # Both types are declared here because rswag 2.x keys the mime list to the
      # operation, not to the response: a 200 is `text/csv` and the 404 is the
      # ordinary JSON error envelope, and there is no supported way to say that in
      # one operation. Passed as separate arguments because the DSL takes a splat
      # — an explicit array arrives nested and stringifies into one bogus key.
      produces    "text/csv", "application/json"

      description <<~DESC
        The file exactly as it was uploaded, sent back under the name it was
        uploaded with (LLD §9.3: the storage key is never exposed).

        Deliberately not a signed storage URL — that would put a token in a URL
        the browser can read and send the user to a different origin. A blob can
        be gone while its attachment record remains, so a missing file is a 404
        with code `file_missing` rather than a 500.
      DESC

      response "200", "the uploaded file" do
        schema type: :string, format: :binary

        let(:id) { create(:salary_import, filename: "q1-salaries.csv", csv_body: "employee_id,effective_date,base_salary,bonus,allowance\n1,2026-01-01,60000,0,0\n").id }
        run_test!
      end

      response "404", "import not found, or the file is gone" do
        schema "$ref" => "#/components/schemas/ErrorEnvelope"

        let(:id) { 999_999 }
        run_test!
      end
    end
  end
end
