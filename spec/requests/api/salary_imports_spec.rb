require "rails_helper"

# FR-4.1 to FR-4.8, FR-6.1 to FR-6.6 / LLD §8 and §9.3 — upload a CSV, watch
# it process, inspect the outcome. The upload endpoint returns the import id
# rather than a processing result; the job is enqueued with that id alone.
RSpec.describe "Salary imports", type: :request do
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

    # LLD §2.6 — the CSV belongs to the import, so the import is what holds the
    # file rather than a key that has to be kept in step with a bucket.
    it "attaches the file to the import" do
      post "/api/v1/salary-imports", params: { file: csv_upload(valid_csv) }

      expect(SalaryImport.last.csv_file).to be_attached
    end

    it "stores what was uploaded, unchanged" do
      post "/api/v1/salary-imports", params: { file: csv_upload(valid_csv) }

      expect(SalaryImport.last.csv_contents).to eq(valid_csv)
    end

    # LLD §9.3 — the attachment is not exposed to the client.
    it "does not expose the attachment" do
      post "/api/v1/salary-imports", params: { file: csv_upload(valid_csv) }

      expect(api_data.keys).not_to include("csv_file")
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

      it "leaves no import behind" do
        post "/api/v1/salary-imports", params: { file: csv_upload(valid_csv, filename: "salaries.txt") }

        # The record and its attachment are saved together, so a rejected file
        # never leaves a pending import or an uploaded object to clean up.
        expect(SalaryImport.count).to eq(0)
        expect(ActiveStorage::Blob.count).to eq(0)
      end

      it "explains why the file was rejected" do
        post "/api/v1/salary-imports", params: { file: csv_upload(valid_csv, filename: "salaries.txt") }

        expect(api_errors.first["message"]).to match(/csv/i)
      end

      # The report a browser showed for this was a minified React error, because
      # Next rejects an oversized action body before the request reaches Rails and
      # has no validation message to send back. The size rules live in the model
      # and the transport limit is raised to clear them, so what is left here is
      # the reason the user should be shown.
      describe "the message the client is shown" do
        it "names the problem for a PDF" do
          post "/api/v1/salary-imports", params: { file: csv_upload("%PDF-1.7", filename: "salaries.pdf", content_type: "application/pdf") }

          expect(response).to have_http_status(:unprocessable_content)
          expect(api_errors.first["message"]).to eq("File must be a CSV file")
        end

        it "says it once for a PDF rather than once per failed check" do
          post "/api/v1/salary-imports", params: { file: csv_upload("%PDF-1.7", filename: "salaries.pdf", content_type: "application/pdf") }

          expect(api_errors.first["message"].scan(/must be a CSV file/).size).to eq(1)
        end

        it "names the problem for a file over 2 MB" do
          post "/api/v1/salary-imports", params: { file: csv_upload("a" * (SalaryImport::MAX_FILE_SIZE + 1)) }

          expect(response).to have_http_status(:unprocessable_content)
          expect(api_errors.first["message"]).to eq("File size must be 2 MB or smaller")
        end
      end

      describe "the daily upload limit" do
        # Exhausting the allowance through 2 MB uploads would mean thirty requests
        # a day; stubbing the total isolates the limit from the per-file rule.
        before { allow(SalaryImport).to receive(:uploaded_bytes_today).and_return(SalaryImport::DAILY_UPLOAD_LIMIT) }

        it "rejects an upload that would cross it" do
          post "/api/v1/salary-imports", params: { file: csv_upload(valid_csv) }

          expect(response).to have_http_status(:unprocessable_content)
          expect(api_errors.first["message"]).to eq("File exceeds your daily upload limit of 60 MB")
        end

        it "stores nothing when it rejects" do
          post "/api/v1/salary-imports", params: { file: csv_upload(valid_csv) }

          expect(SalaryImport.count).to eq(0)
          expect(ActiveStorage::Blob.count).to eq(0)
        end

        it "does not enqueue the job" do
          post "/api/v1/salary-imports", params: { file: csv_upload(valid_csv) }

          expect(jobs_for("SalaryImportJob")).to be_empty
        end

        it "is the uploader's own allowance, not a global one" do
          allow(SalaryImport).to receive(:uploaded_bytes_today).and_return(0)
          other = create(:user)

          post "/api/v1/salary-imports", params: { file: csv_upload(valid_csv) }

          expect(response).to have_http_status(:created)
          expect(SalaryImport.last.created_by).to eq(hr_manager.id)
          expect(other.id).not_to eq(hr_manager.id)
        end
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

      expect(api_data.first).not_to have_key("csv_file")
    end

    it "returns an empty list when there are no imports" do
      get "/api/v1/salary-imports"

      expect(api_data).to be_empty
    end

    # The list is the only place the person who ran an import is recorded, and a
    # bare `created_by` id means nothing to a reader.
    it "reports the uploader's email rather than the raw id" do
      uploader = create(:user)
      create(:salary_import, created_by: uploader.id)

      get "/api/v1/salary-imports"

      expect(api_data.first["created_by"]).to eq(uploader.email)
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

      expect(api_data).not_to have_key("csv_file")
    end
  end

  describe "GET /api/v1/salary-imports/:id/errors" do
    let(:salary_import) { create(:salary_import, :completed_with_errors) }

    it "returns the failing rows" do
      employee_record = create(:employee)
      create(:salary_import_error,
             salary_import: salary_import,
             employee: employee_record,
             row_number: 4,
             error_message: "Invalid base_salary 'abc'",
             raw_data: { "employee_id" => "7", "base_salary" => "abc" })

      get "/api/v1/salary-imports/#{salary_import.id}/errors"

      expect(response).to have_http_status(:ok)
      expect(api_data.first).to include(
        "row_number" => 4,
        "employee_id" => employee_record.id,
        "error_message" => "Invalid base_salary 'abc'",
        "raw_data" => { "employee_id" => "7", "base_salary" => "abc" }
      )
    end

    # A row that fails on its employee_id has none to report; the column is
    # allowed to be null rather than carrying a placeholder.
    it "returns a null employee_id when the row had none" do
      create(:salary_import_error, salary_import: salary_import, employee: nil)

      get "/api/v1/salary-imports/#{salary_import.id}/errors"

      expect(api_data.first).to include("employee_id" => nil)
    end

    it "returns an empty page for an import that failed nothing" do
      get "/api/v1/salary-imports/#{create(:salary_import, :completed).id}/errors"

      expect(response).to have_http_status(:ok)
      expect(api_data).to be_empty
      expect(response.parsed_body["summary"]).to eq([])
    end

    it "only returns errors belonging to the requested import" do
      create(:salary_import_error, salary_import: salary_import)
      create(:salary_import_error)

      get "/api/v1/salary-imports/#{salary_import.id}/errors"

      expect(api_data.size).to eq(1)
    end

    describe "ordering and pagination" do
      it "orders by row number" do
        create(:salary_import_error, salary_import: salary_import, row_number: 7)
        create(:salary_import_error, salary_import: salary_import, row_number: 2)
        create(:salary_import_error, salary_import: salary_import, row_number: 4)

        get "/api/v1/salary-imports/#{salary_import.id}/errors"

        expect(api_data.map { |row| row["row_number"] }).to eq([ 2, 4, 7 ])
      end

      # An import over the full dataset can reject most of its rows, so the page
      # is capped rather than returning every error at once.
      it "returns 50 rows per page with a total count" do
        create_list(:salary_import_error, 60, salary_import: salary_import)

        get "/api/v1/salary-imports/#{salary_import.id}/errors"

        expect(api_data.size).to eq(50)
        expect(response.parsed_body.dig("meta", "per_page")).to eq(50)
        expect(response.parsed_body.dig("meta", "total_count")).to eq(60)
        expect(response.parsed_body.dig("meta", "total_pages")).to eq(2)
      end

      it "returns the rows for the requested page" do
        create_list(:salary_import_error, 60, salary_import: salary_import)

        get "/api/v1/salary-imports/#{salary_import.id}/errors", params: { page: 2 }

        expect(api_data.size).to eq(10)
        expect(response.parsed_body.dig("meta", "current_page")).to eq(2)
      end

      it "treats a missing or nonsensical page as the first one" do
        create_list(:salary_import_error, 2, salary_import: salary_import)

        get "/api/v1/salary-imports/#{salary_import.id}/errors", params: { page: "not-a-page" }

        expect(response.parsed_body.dig("meta", "current_page")).to eq(1)
        expect(api_data.size).to eq(2)
      end
    end

    # The summary is the roll-up of the same rows as the page, so the counts
    # always reconcile with meta.total_count.
    describe "summary" do
      it "groups the rows by reason, most frequent first" do
        create(:salary_import_error, salary_import: salary_import, error_message: "Unknown employee 999999")
        create(:salary_import_error, salary_import: salary_import, error_message: "Unknown employee 999999")
        create(:salary_import_error, salary_import: salary_import, error_message: "Missing effective_date")

        get "/api/v1/salary-imports/#{salary_import.id}/errors"

        expect(response.parsed_body["summary"]).to eq([
          { "error_message" => "Unknown employee 999999", "count" => 2 },
          { "error_message" => "Missing effective_date", "count" => 1 }
        ])
      end

      it "counts a whole-file failure alongside the row failures" do
        create(:salary_import_error, salary_import: salary_import, error_message: "ArgumentError: invalid CSV headers")
        create(:salary_import_error, salary_import: salary_import, error_message: "Unknown employee 999999")

        get "/api/v1/salary-imports/#{salary_import.id}/errors"

        expect(response.parsed_body["summary"].map { |row| row["count"] }).to eq([ 1, 1 ])
        expect(response.parsed_body.dig("meta", "total_count")).to eq(2)
      end
    end

    it "returns 404 for an unknown import" do
      get "/api/v1/salary-imports/999999/errors"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/v1/salary-imports/:id/csv" do
    let(:body) { csv_from_rows([ row ]) }
    let(:row) { { "employee_id" => employee.id.to_s, "effective_date" => "2026-01-01",
                  "base_salary" => "60000", "bonus" => "0", "allowance" => "0" } }
    let(:salary_import) { create(:salary_import, filename: "q1-salaries.csv", csv_body: body) }

    it "returns the uploaded file" do
      get "/api/v1/salary-imports/#{salary_import.id}/csv"

      expect(response).to have_http_status(:ok)
      expect(response.body).to eq(body)
    end

    it "sends it as an attachment under the name it was uploaded with" do
      get "/api/v1/salary-imports/#{salary_import.id}/csv"

      expect(response.headers["Content-Disposition"]).to include("attachment")
      expect(response.headers["Content-Disposition"]).to include("q1-salaries.csv")
      expect(response.media_type).to eq("text/csv")
    end

    # The storage key is the one thing that must not leave the API: a URL or key
    # in a response is a path to the bucket.
    it "does not expose the storage key" do
      get "/api/v1/salary-imports/#{salary_import.id}/csv"

      blob = salary_import.csv_file.blob
      expect(response.body).not_to include(blob.key)
      expect(response.headers.to_h.to_s).not_to include(blob.key)
    end

    it "returns 404 for an unknown import" do
      get "/api/v1/salary-imports/999999/csv"

      expect(response).to have_http_status(:not_found)
    end

    # A purged blob leaves the attachment record in place, which is the state the
    # job's `rescue` exists for.
    it "returns 404 when the file itself is gone" do
      salary_import.csv_file.purge

      get "/api/v1/salary-imports/#{salary_import.id}/csv"

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body.dig("errors", 0, "code")).to eq("file_missing")
    end

    # A filename is echoed into a response header, so a crafted upload must not be
    # able to smuggle a newline in there.
    it "strips characters that could break the content-disposition header" do
      salary_import.update!(filename: %(evil"\r\nX-Injected: 1.csv))

      get "/api/v1/salary-imports/#{salary_import.id}/csv"

      expect(response).to have_http_status(:ok)
      expect(response.headers["X-Injected"]).to be_nil
      expect(response.headers["Content-Disposition"]).not_to include("\n")
    end

    it "falls back to a name when the filename sanitises away to nothing" do
      salary_import.update!(filename: %("))

      get "/api/v1/salary-imports/#{salary_import.id}/csv"

      expect(response).to have_http_status(:ok)
      expect(response.headers["Content-Disposition"]).to include("salary-import.csv")
    end
  end
end
