require "rails_helper"

# FR-1.1 / LLD §10.1 — a single employee, addressed by id.
RSpec.describe "GET /api/v1/employees/:id", type: :request do
  let(:employee) do
    create(:employee,
      first_name: "Ada",
      last_name: "Lovelace",
      email: "ada@example.com",
      department: ReferenceData.department("Engineering"),
      country: ReferenceData.country("United Kingdom", "GBP"),
      hire_date: Date.new(2019, 3, 1)
    )
  end

  it "returns the employee" do
    get "/api/v1/employees/#{employee.id}"

    expect(response).to have_http_status(:ok)
    expect(api_data).to be_present
  end

  it "exposes the id and the name" do
    get "/api/v1/employees/#{employee.id}"

    expect(api_data).to include("id" => employee.id, "name" => "Ada Lovelace")
  end

  it "exposes the directory attributes" do
    get "/api/v1/employees/#{employee.id}"

    expect(api_data).to include(
      "email" => "ada@example.com",
      "department" => "Engineering",
      "country" => "United Kingdom",
      "hire_date" => "2019-03-01"
    )
  end

  # BR-8, LLD §2.3 — money is always shown in the employee's own currency, and
  # that currency is the one their country is paid in, not a value on the
  # employee. Ada is in the United Kingdom, so the detail view names GBP.
  it "names the currency of the employee's country" do
    get "/api/v1/employees/#{employee.id}"

    expect(api_currency_code).to eq("GBP")
  end

  it "returns 404 for an unknown id" do
    get "/api/v1/employees/999999"

    expect(response).to have_http_status(:not_found)
  end

  it "returns an errors envelope for an unknown id" do
    get "/api/v1/employees/999999"

    expect(api_errors).to be_present
  end

  it "does not return another employee's record" do
    get "/api/v1/employees/#{employee.id}"

    expect(api_data["email"]).to eq("ada@example.com")
  end
end
