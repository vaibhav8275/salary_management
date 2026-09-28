require "rails_helper"

# FR-4.1 to FR-4.8, FR-6.1 to FR-6.6 / LLD §8 and §10.3 — upload a CSV, watch
# it process, inspect the outcome. The upload endpoint returns the import id
# rather than a processing result; the job is enqueued with that id alone.
RSpec.describe "Salary imports", :s3, type: :request do
  let(:employee) { create(:employee) }

  def csv_upload(body, filename: "salaries.csv", content_type: "text/csv")
    Rack::Test::UploadedFile.new(StringIO.new(body), content_type, original_filename: filename)
  end

  def valid_csv
    csv_from_rows(
      [ { "employee_id" => employee.id.to_s, "effective_date" => "2026-01-01",
         "base_salary" => "60000", "bonus" => "0", "allowance" => "0" } ]
    )
  end

  describe "POST /api/v1/salary-imports" do
    it "creates the import" do
      post "/api/v1/salary-imports", params: { file: csv_upload(valid_csv) }

      expect(response).to have_http_status(:created)
      expect(SalaryImport.count).to eq(1)
    end

    # LLD §8.1 — the response is the import id, not a processing result.
    it "returns the import id" do
      post "/api/v1/salary-imports", params: { file: csv_upload(valid_csv) }

      expect(api_data["id"]).to eq(SalaryImport.last.id)
    end

    it "starts the import as pending" do
      post "/api/v1/salary-imports", params: { file: csv_upload(valid_csv) }

      expect(SalaryImport.last.status).to eq("pending")
    end

    it "records the filename" do
      post "/api/v1/salary-imports", params: { file: csv_upload(valid_csv, filename: "q3-salaries.csv") }

      expect(SalaryImport.last.filename).to eq("q3-salaries.csv")
    end

    it "uploads the file to storage and keeps only the key" do
      post "/api/v1/salary-imports", params: { file: csv_upload(valid_csv) }

      expect(S3TestDouble.contents.keys).to eq([ SalaryImport.last.s3_object_key ])
    end

    # LLD §10.3 — the s3 key is not exposed to the client.
    it "does not expose the s3 key" do
      post "/api/v1/salary-imports", params: { file: csv_upload(valid_csv) }

      expect(api_data).not_to have_key("s3_object_key")
    end

    it "records the uploading user" do
      post "/api/v1/salary-imports", params: { file: csv_upload(valid_csv) }

      expect(SalaryImport.last.created_by).to be_present
    end

    # LLD §8.1 — the job is handed the import id alone.
    it "enqueues the processing job" do
      post "/api/v1/salary-imports", params: { file: csv_upload(valid_csv) }

      expect(jobs_for("SalaryImportJob").size).to eq(1)
    end

    it "enqueues the job with the import id only" do
      post "/api/v1/salary-imports", params: { file: csv_upload(valid_csv) }

      expect(jobs_for("SalaryImportJob").last["args"]).to eq([ SalaryImport.last.id ])
    end

    it "does not process the file synchronously" do
      post "/api/v1/salary-imports", params: { file: csv_upload(valid_csv) }

      expect(SalaryRecord.where(employee_id: employee.id).count).to eq(0)
    end

    describe "file validation" do
      # LLD §13 — file type validation on upload.
      it "rejects a non CSV file" do
        post "/api/v1/salary-imports", params: { file: csv_upload("binary", filename: "salaries.xlsx", content_type: "application/vnd.ms-excel") }

        expect(response).to have_http_status(:unprocessable_content)
        expect(SalaryImport.count).to eq(0)
      end

      it "rejects a request with no file" do
        post "/api/v1/salary-imports"

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "rejects a file with the wrong extension" do
        post "/api/v1/salary-imports", params: { file: csv_upload(valid_csv, filename: "salaries.txt") }

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "returns an errors envelope" do
        post "/api/v1/salary-imports"

        expect(api_errors).to be_present
      end
    end
  end

  describe "GET /api/v1/salary-imports" do
    it "lists the imports" do
      create(:salary_import)
      create(:salary_import)

      get "/api/v1/salary-imports"

      expect(response).to have_http_status(:ok)
      expect(api_data.size).to eq(2)
    end

    it "orders the newest first" do
      older = create(:salary_import)
      newer = create(:salary_import)

      get "/api/v1/salary-imports"

      expect(api_data.map { |row| row["id"] }).to eq([ newer.id, older.id ])
    end

    # FR-6.2 — the list shows where an import got to.
    it "exposes the status and the counters" do
      create(:salary_import, :completed_with_errors)

      get "/api/v1/salary-imports"

      expect(api_data.first).to include(
        "status" => "completed_with_errors",
        "total_records" => 10,
        "processed_records" => 9,
        "failed_records" => 1
      )
    end

    it "does not expose the s3 key" do
      create(:salary_import)

      get "/api/v1/salary-imports"

      expect(api_data.first).not_to have_key("s3_object_key")
    end

    it "returns an empty list when there are no imports" do
      get "/api/v1/salary-imports"

      expect(api_data).to be_empty
    end
  end

  describe "GET /api/v1/salary-imports/:id" do
    it "returns the import" do
      salary_import = create(:salary_import, :processing)

      get "/api/v1/salary-imports/#{salary_import.id}"

      expect(response).to have_http_status(:ok)
      expect(api_data).to include("id" => salary_import.id, "status" => "processing")
    end

    # FR-6.3 — the frontend polls this to show progress.
    it "exposes the counters for polling" do
      salary_import = create(:salary_import, :processing, failed_records: 2)

      get "/api/v1/salary-imports/#{salary_import.id}"

      expect(api_data).to include("total_records" => 100, "processed_records" => 40, "failed_records" => 2)
    end

    it "reports the failures for the import" do
      salary_import = create(:salary_import, :completed_with_errors)
      create(:salary_import_error, salary_import: salary_import, row_number: 3, error_message: "Unknown employee 999999")

      get "/api/v1/salary-imports/#{salary_import.id}"

      expect(api_data["failed_records"]).to eq(1)
    end

    it "returns 404 for an unknown import" do
      get "/api/v1/salary-imports/999999"

      expect(response).to have_http_status(:not_found)
    end

    it "does not expose the s3 key" do
      salary_import = create(:salary_import)

      get "/api/v1/salary-imports/#{salary_import.id}"

      expect(api_data).not_to have_key("s3_object_key")
    end
  end
end
