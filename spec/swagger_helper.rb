require "rails_helper"

RSpec.configure do |config|
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
        DESC
      },
      servers: [
        { url: "http://localhost:3000", description: "Local development" }
      ],
      components: {
        schemas: {
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
              created_at:        { type: :string,  format: "date-time" }
            },
            required: %w[id filename status total_records processed_records failed_records]
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
          EmployeeCountRow: {
            type: :object,
            properties: {
              department: { type: :string,  example: "Engineering" },
              country:    { type: :string,  example: "United States" },
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
