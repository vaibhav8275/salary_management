require "rails_helper"

# LLD §13 — controlled error responses, input validation, and CORS for a
# browser client on another origin. Errors are reported in the `errors`
# envelope, never as a stack trace or a raw database message.
RSpec.describe "API error handling and CORS", type: :request do
  # The initializer reads this at boot, so the test reads the same source rather
  # than hard-coding an origin that could drift from the configuration.
  let(:frontend_origin) { ENV.fetch("FRONTEND_ORIGIN", "http://localhost:3000") }

  describe "unknown resources" do
    it "returns 404 for an unknown employee" do
      get "/api/v1/employees/999999"

      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for an unknown salary record" do
      employee = create(:employee)
      create(:salary_record, employee: employee)

      patch "/api/v1/employees/#{employee.id}/salary/999999", params: { base_salary: "1" }

      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for an unknown route" do
      get "/api/v1/nothing-here"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "the error envelope" do
    it "uses the errors key" do
      get "/api/v1/employees/999999"

      expect(api_errors).to be_present
    end

    it "describes the problem" do
      get "/api/v1/employees/999999"

      expect(api_errors.to_s).to be_present
    end

    # LLD §13 — a database message must never reach the client.
    it "does not leak the database adapter" do
      get "/api/v1/employees/999999"

      expect(api_response_body).not_to include("PG::")
    end

    it "does not leak a backtrace" do
      get "/api/v1/employees/999999"

      expect(api_response_body).not_to include("app/controllers")
    end
  end

  describe "malformed input" do
    let(:employee) { create(:employee) }

    it "rejects a non numeric salary" do
      post "/api/v1/employees/#{employee.id}/salary",
           params: { base_salary: "abc", effective_date: "2026-01-01" }

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "rejects an unparseable date" do
      post "/api/v1/employees/#{employee.id}/salary",
           params: { base_salary: "100", effective_date: "not-a-date" }

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "ignores an unknown filter rather than failing" do
      create(:employee, department: ReferenceData.department("Engineering"))

      get "/api/v1/employees", params: { department: "Engineering", salary_band: "high" }

      expect(response).to have_http_status(:ok)
      expect(api_data.size).to eq(1)
    end

    it "ignores an unpermitted parameter instead of using it" do
      create(:salary_record, employee: employee, effective_date: Date.new(2026, 1, 1), base_salary: 50_000)

      patch "/api/v1/employees/#{employee.id}/salary/#{SalaryRecord.last.id}",
            params: { base_salary: "60000", employee_id: create(:employee).id }

      expect(SalaryRecord.last.reload.employee_id).to eq(employee.id)
    end
  end

  describe "CORS" do
    # The API is consumed by a browser client served from another origin.
    it "allows the configured origin" do
      get "/api/v1/employees", headers: { "Origin" => frontend_origin }

      expect(response.headers["Access-Control-Allow-Origin"]).to eq(frontend_origin)
    end

    it "allows the requested methods" do
      get "/api/v1/employees", headers: { "Origin" => frontend_origin }

      expect(response.headers["Access-Control-Allow-Methods"]).to include("GET")
    end

    it "answers a preflight request" do
      process :options, "/api/v1/employees", headers: {
        "Origin" => frontend_origin,
        "Access-Control-Request-Method" => "POST"
      }

      expect(response).to have_http_status(:no_content).or have_http_status(:ok)
    end

    it "does not allow an unlisted origin" do
      get "/api/v1/employees", headers: { "Origin" => "http://evil.example.com" }

      expect(response.headers["Access-Control-Allow-Origin"]).to be_blank
    end
  end
end
