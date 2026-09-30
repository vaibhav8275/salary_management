require "rails_helper"

# FR-1.1 to FR-1.7 / LLD §9.1 — the employee directory. Around 10,000 employees
# are in scope, so search, filtering and pagination all have to work at that size.
#
# The response envelope is not specified in the LLD ("exact naming and response
# contracts are finalized during implementation"). These examples assume a
# `{ "data": ..., "meta": ... }` envelope with pagination metadata in `meta`, which
# is the same assumption the Cucumber steps make. If the contract lands
# differently, ApiResponseHelpers is the single place to change.
RSpec.describe "GET /api/v1/employees", type: :request do
  describe "listing" do
    it "returns the employees" do
      create(:employee, first_name: "Ada", last_name: "Lovelace")

      get "/api/v1/employees"

      expect(response).to have_http_status(:ok)
      expect(api_data.size).to eq(1)
    end

    it "exposes the id and the name" do
      employee = create(:employee, first_name: "Ada", last_name: "Lovelace")

      get "/api/v1/employees"

      expect(api_data.first).to include("id" => employee.id, "name" => "Ada Lovelace")
    end

    it "exposes the directory attributes" do
      employee = create(:employee,
        first_name: "Ada", last_name: "Lovelace", email: "ada@example.com",
        department: ReferenceData.department("Engineering"),
        job_title: ReferenceData.job_title("Senior Software Engineer"),
        country: ReferenceData.country("United Kingdom", "GBP"),
        hire_date: Date.new(2019, 3, 1)
      )

      get "/api/v1/employees"

      entry = api_data.first
      expect(entry).to include(
        "email" => "ada@example.com",
        "department" => "Engineering",
        "job_title" => "Senior Software Engineer",
        "country" => "United Kingdom",
        "hire_date" => "2019-03-01"
      )
      expect(entry["id"]).to eq(employee.id)
    end

    it "is ordered by id" do
      first = create(:employee)
      second = create(:employee)

      get "/api/v1/employees"

      expect(api_data.map { |row| row["id"] }).to eq([ first.id, second.id ])
    end
  end

  describe "search" do
    # FR-1.3
    it "matches on the first name" do
      create(:employee, first_name: "Ada", last_name: "Lovelace")
      create(:employee, first_name: "Grace", last_name: "Hopper")

      get "/api/v1/employees", params: { search: "Ada" }

      expect(api_data.size).to eq(1)
    end

    it "matches on the last name" do
      create(:employee, first_name: "Ada", last_name: "Lovelace")
      create(:employee, first_name: "Grace", last_name: "Hopper")

      get "/api/v1/employees", params: { search: "Hopper" }

      expect(api_data.first["name"]).to eq("Grace Hopper")
    end

    it "matches on the full name" do
      create(:employee, first_name: "Ada", last_name: "Lovelace")
      create(:employee, first_name: "Grace", last_name: "Hopper")

      get "/api/v1/employees", params: { search: "Ada Lovelace" }

      expect(api_data.size).to eq(1)
    end

    it "matches on the email" do
      create(:employee, first_name: "Ada", last_name: "Lovelace", email: "ada@example.com")
      create(:employee, first_name: "Grace", last_name: "Hopper", email: "grace@example.com")

      get "/api/v1/employees", params: { search: "ada@example.com" }

      expect(api_data.size).to eq(1)
    end

    it "matches on the employee id" do
      employee = create(:employee, first_name: "Ada", last_name: "Lovelace")
      create(:employee, first_name: "Grace", last_name: "Hopper")

      get "/api/v1/employees", params: { search: employee.id.to_s }

      expect(api_data.size).to eq(1)
    end

    it "is case insensitive" do
      create(:employee, first_name: "Ada", last_name: "Lovelace")
      create(:employee, first_name: "Grace", last_name: "Hopper")

      get "/api/v1/employees", params: { search: "ada" }

      expect(api_data.size).to eq(1)
    end

    it "returns an empty list when nothing matches" do
      create(:employee, first_name: "Ada", last_name: "Lovelace")

      get "/api/v1/employees", params: { search: "Nobody" }

      expect(api_data).to be_empty
    end
  end

  describe "filtering" do
    it "filters by department" do
      create(:employee, department: ReferenceData.department("Engineering"))
      create(:employee, department: ReferenceData.department("Sales"))

      get "/api/v1/employees", params: { department: "Engineering" }

      expect(api_data.size).to eq(1)
    end

    it "filters by country" do
      create(:employee, country: ReferenceData.country("United Kingdom"))
      create(:employee, country: ReferenceData.country("Nigeria"))

      get "/api/v1/employees", params: { country: "United Kingdom" }

      expect(api_data.size).to eq(1)
    end

    it "filters by job title" do
      create(:employee, job_title: ReferenceData.job_title("Software Engineer"))
      create(:employee, job_title: ReferenceData.job_title("Accountant"))

      get "/api/v1/employees", params: { job_title: "Accountant" }

      expect(api_data.size).to eq(1)
      expect(api_data.first["job_title"]).to eq("Accountant")
    end

    it "returns nothing for a job title no one holds" do
      create(:employee, job_title: ReferenceData.job_title("Software Engineer"))

      get "/api/v1/employees", params: { job_title: "Astronaut" }

      expect(api_data).to be_empty
    end

    it "combines all three filters" do
      create(:employee, department: ReferenceData.department("Engineering"),
                         job_title: ReferenceData.job_title("Software Engineer"),
                         country: ReferenceData.country("United Kingdom"))
      create(:employee, department: ReferenceData.department("Engineering"),
                         job_title: ReferenceData.job_title("Software Engineer"),
                         country: ReferenceData.country("Nigeria"))
      create(:employee, department: ReferenceData.department("Sales"),
                         job_title: ReferenceData.job_title("Software Engineer"),
                         country: ReferenceData.country("United Kingdom"))

      get "/api/v1/employees", params: {
        department: "Engineering", job_title: "Software Engineer", country: "United Kingdom"
      }

      expect(api_data.size).to eq(1)
      expect(api_data.first["country"]).to eq("United Kingdom")
    end

    it "combines a search term with a filter" do
      create(:employee, first_name: "Ada", last_name: "Lovelace", department: ReferenceData.department("Engineering"))
      create(:employee, first_name: "Ada", last_name: "Byron", department: ReferenceData.department("Sales"))

      get "/api/v1/employees", params: { search: "Ada", department: "Engineering" }

      expect(api_data.size).to eq(1)
    end

    # The search box advertises "job title", so the term has to reach the title.
    it "searches by job title" do
      create(:employee, first_name: "Grace", job_title: ReferenceData.job_title("Rear Admiral"))
      create(:employee, first_name: "Katherine", job_title: ReferenceData.job_title("Aeronautics Engineer"))

      get "/api/v1/employees", params: { search: "Rear Admiral" }

      expect(api_data.size).to eq(1)
      expect(api_data.first["first_name"]).to eq("Grace")
    end
  end

  describe "pagination" do
    before { 12.times { create(:employee) } }

    it "returns the requested page" do
      get "/api/v1/employees", params: { page: 2, per_page: 5 }

      expect(api_data.size).to eq(5)
    end

    it "does not repeat a row across pages" do
      get "/api/v1/employees", params: { page: 1, per_page: 5 }
      first_page = api_data.map { |row| row["id"] }

      get "/api/v1/employees", params: { page: 2, per_page: 5 }
      second_page = api_data.map { |row| row["id"] }

      expect(first_page & second_page).to be_empty
    end

    it "reports the page size in the metadata" do
      get "/api/v1/employees", params: { page: 1, per_page: 5 }

      expect(api_meta["per_page"]).to eq(5)
    end

    it "reports the total count in the metadata" do
      get "/api/v1/employees", params: { per_page: 5 }

      expect(api_meta["total_count"]).to eq(12)
    end

    it "reports the current page in the metadata" do
      get "/api/v1/employees", params: { page: 2, per_page: 5 }

      expect(api_meta["current_page"]).to eq(2)
    end

    it "reports the number of pages" do
      get "/api/v1/employees", params: { per_page: 5 }

      expect(api_meta["total_pages"]).to eq(3)
    end

    it "returns an empty page beyond the end" do
      get "/api/v1/employees", params: { page: 9, per_page: 10 }

      expect(api_data).to be_empty
    end
  end

  describe "FR-1.7 — the directory stays usable at scale" do
    it "returns a page of results from 10,000 employees" do
      10_000.times { create(:employee) }

      get "/api/v1/employees", params: { page: 1, per_page: 10 }

      expect(response).to have_http_status(:ok)
      expect(api_data.size).to eq(10)
      expect(api_meta["total_count"]).to eq(10_000)
    end

    it "finds a match among 10,000 employees" do
      10_000.times { create(:employee) }
      target = create(:employee, first_name: "Ada", last_name: "Lovelace", email: "needle@example.com")

      get "/api/v1/employees", params: { search: "needle@example.com" }

      expect(api_data.map { |row| row["id"] }).to eq([ target.id ])
    end
  end
end
