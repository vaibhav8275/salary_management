require "rails_helper"

# The bearer token for the documented requests.
#
# rswag turns the document-level `security` declared below into a required
# `Authorization` header parameter on every example, and reads the value from a
# `let` named after the parameter
# (rswag-specs `request_factory.rb` `derive_security_params` / `extract_getter`).
# Without this, each documented request would fail with
# `undefined method 'Authorization'` before it reached the application.
#
# The value is the same header the request specs use, so a documented example
# and its RSpec equivalent authenticate identically. It is a `let` rather than
# something in a `before` hook so no user is created for the operations that do
# not ask for a token.
RSpec.shared_context "documented api requests" do
  let(:Authorization) { auth_headers.fetch("Authorization") }
end

RSpec.configure do |config|
  # Applies to the swagger example groups, which are declared `type: :request`,
  # and harmlessly to the other request specs: the `let` is only read when
  # something builds a documented request.
  config.include_context "documented api requests", type: :request

  # Directory where swagger.json is written (must exist before swaggerize runs).
  config.openapi_root = Rails.root.join("swagger").to_s

  # openapi_specs maps output file paths (relative to openapi_root) to the
  # base OpenAPI document they describe.
  config.openapi_specs = {
    "v1/swagger.json" => {
      openapi: "3.0.1",
      info: {
        title: "Salary Management API",
        version: "v1",
        description: <<~DESC
          REST API for the Salary Management system.
          Handles the employee directory, salary records, bulk imports and reporting.

          ## Authentication

          Every endpoint needs the token issued by `POST /api/v1/auth/login`
          (LLD §9.4). Sign in there, then use the **Authorize** button at the top
          of this page to paste the token value; the docs and every request will
          carry it as `Authorization: Bearer <token>`.

          The token is returned in the `Authorization` *response* header of the
          sign-in call. Take everything after `Bearer ` when pasting it into
          **Authorize** — the field takes the token itself, not the header.
        DESC
      },
      servers: [
        { url: "http://localhost:3000", description: "Local development" }
      ],
      # Declared once for the whole document rather than repeated per operation:
      # the API has exactly one authentication scheme and it applies to
      # everything. `POST /api/v1/auth/login` opts out with `security: []`,
      # because it is where the token comes from.
      security: [
        { bearerAuth: [] }
      ],
      components: {
        # The `Authorize` button in the docs is generated from this scheme, so
        # naming it here is what makes the token usable from the documentation
        # rather than something a reader has to construct by hand.
        securitySchemes: {
          bearerAuth: {
            type: :http,
            scheme: :bearer,
            bearerFormat: "JWT",
            description: "The JWT returned in the `Authorization` response header " \
                         "of `POST /api/v1/auth/login`. Paste the token without the " \
                         "`Bearer ` prefix. Tokens are not revocable and expire on " \
                         "their own (LLD §9.4)."
          }
        },
        schemas: {
          # ── Authentication ───────────────────────────────────────────────
          # The credentials are nested under `user` because that is the key
          # Devise's warden strategy reads them from, not a shape chosen for
          # the document.
          LoginRequest: {
            type: :object,
            properties: {
              user: {
                type: :object,
                properties: {
                  email:    { type: :string, format: :email, example: "hr@example.com" },
                  password: { type: :string, format: :password }
                },
                required: %w[email password]
              }
            },
            required: %w[user]
          },
          # Deliberately not the `User` model: the response says who signed in
          # and never carries the password digest.
          SignedInUser: {
            type: :object,
            properties: {
              email: { type: :string, format: :email, example: "hr@example.com" }
            },
            required: %w[email]
          },
          # ── Shared primitives ──────────────────────────────────────────────
          Error: {
            type: :object,
            properties: {
              code:    { type: :string, example: "not_found" },
              message: { type: :string, example: "resource not found" }
            },
            required: %w[code message]
          },
          ErrorEnvelope: {
            type: :object,
            properties: {
              errors: {
                type: :array,
                items: { "$ref" => "#/components/schemas/Error" }
              }
            },
            required: %w[errors]
          },
          PaginationMeta: {
            type: :object,
            properties: {
              current_page: { type: :integer, example: 1 },
              per_page:     { type: :integer, example: 25 },
              total_count:  { type: :integer, example: 100 },
              total_pages:  { type: :integer, example: 4 }
            },
            required: %w[current_page per_page total_count total_pages]
          },
          Currency: {
            type: :object,
            properties: {
              id:     { type: :integer },
              code:   { type: :string,  example: "USD" },
              name:   { type: :string,  example: "US Dollar" },
              symbol: { type: :string,  example: "$" }
            },
            required: %w[code name symbol]
          },
          # ── Employee ──────────────────────────────────────────────────────
          Employee: {
            type: :object,
            properties: {
              id:         { type: :integer },
              name:       { type: :string, example: "Ada Lovelace" },
              first_name: { type: :string, example: "Ada" },
              last_name:  { type: :string, example: "Lovelace" },
              email:      { type: :string, format: :email },
              department: { type: :string, example: "Engineering" },
              job_title:  { type: :string, example: "Senior Software Engineer" },
              country:    { type: :string, example: "United Kingdom" },
              hire_date:  { type: :string, format: :date, example: "2019-03-01" }
            },
            required: %w[id name email department job_title country hire_date]
          },
          EmployeeDetail: {
            allOf: [
              { "$ref" => "#/components/schemas/Employee" },
              {
                type: :object,
                properties: {
                  currency: { "$ref" => "#/components/schemas/Currency" }
                },
                required: %w[currency]
              }
            ]
          },
          # ── Salary record ─────────────────────────────────────────────────
          SalaryRecord: {
            type: :object,
            properties: {
              id:             { type: :integer },
              base_salary:    { type: :string, format: :decimal, example: "50000.0" },
              bonus:          { type: :string, format: :decimal, example: "1000.0" },
              allowance:      { type: :string, format: :decimal, example: "500.0" },
              effective_date: { type: :string, format: :date,    example: "2026-01-01" },
              currency:       { "$ref" => "#/components/schemas/Currency" }
            },
            required: %w[id base_salary bonus allowance effective_date currency]
          },
          # ── Salary audit entry ────────────────────────────────────────────
          SalaryAudit: {
            type: :object,
            properties: {
              id:               { type: :integer },
              whodunnit:        { type: :string,  example: "HR Manager" },
              event:            { type: :string,  example: "create" },
              source:           { type: :string,  example: "manual" },
              salary_import_id: { type: :integer, nullable: true },
              created_at:       { type: :string,  format: "date-time" },
              changed_by:       { type: :string,  example: "HR Manager" },
              changed_at:       { type: :string,  format: "date-time" },
              salary_record_id: { type: :integer },
              changes:          { type: :object },
              changeset:        { type: :object }
            }
          },
          # ── Salary import ─────────────────────────────────────────────────
          SalaryImport: {
            type: :object,
            properties: {
              id:                { type: :integer },
              filename:          { type: :string,  example: "salaries-q1.csv" },
              status:            { type: :string,  enum: %w[pending processing completed completed_with_errors failed] },
              total_records:     { type: :integer, example: 200 },
              processed_records: { type: :integer, example: 198 },
              failed_records:    { type: :integer, example: 2 },
              # The uploader's email, not the raw created_by id: null when the
              # account behind the import no longer exists.
              created_by:        { type: :string,  example: "hr.manager1@example.com", nullable: true },
              created_at:        { type: :string,  format: "date-time" }
            },
            required: %w[id filename status total_records processed_records failed_records]
          },
          SalaryImportError: {
            type: :object,
            properties: {
              id:            { type: :integer },
              # 0 marks the synthetic row that carries a whole-file failure reason,
              # as opposed to a line in the CSV.
              row_number:    { type: :integer, example: 4 },
              # Null when the row could not be resolved to an employee — a blank
              # or unknown employee_id is itself a reason for failure.
              employee_id:   { type: :integer, example: 42, nullable: true },
              error_message: { type: :string,  example: "Invalid base_salary 'abc'" },
              raw_data:      { type: :object, additionalProperties: true,
                               example: { "employee_id" => "7", "base_salary" => "abc" } },
              created_at:    { type: :string,  format: "date-time" }
            },
            required: %w[id row_number error_message raw_data]
          },
          SalaryImportErrorSummaryRow: {
            type: :object,
            properties: {
              error_message: { type: :string,  example: "Unknown employee 999999" },
              count:         { type: :integer, example: 12 }
            },
            required: %w[error_message count]
          },
          # ── Report rows ───────────────────────────────────────────────────
          ReportRow: {
            type: :object,
            properties: {
              amount:     { type: :string, format: :decimal, example: "60000.0" },
              currency:   { type: :string, example: "USD" },
              department: { type: :string, example: "Engineering" },
              country:    { type: :string, example: "United States" }
            }
          },
          DistributionRow: {
            type: :object,
            properties: {
              range:    { type: :string,  example: "50000-75000" },
              count:    { type: :integer, example: 42 },
              currency: { type: :string,  example: "USD" }
            },
            required: %w[range count currency]
          },
          TrendRow: {
            type: :object,
            properties: {
              effective_date: { type: :string, format: :date, example: "2026-01-01" },
              currency:       { type: :string, example: "USD" },
              amount:         { type: :string, format: :decimal, example: "55000.0" }
            },
            required: %w[effective_date currency amount]
          },
          # One key is present per `group_by`; only `count` is always there.
          EmployeeCountRow: {
            type: :object,
            properties: {
              department: { type: :string,  example: "Engineering" },
              country:    { type: :string,  example: "United States" },
              job_title:  { type: :string,  example: "Software Engineer" },
              count:      { type: :integer, example: 15 }
            },
            required: %w[count]
          }
        }
      }
    }
  }

  # Output format — rswag can write JSON or YAML.
  config.openapi_format = :json
end
