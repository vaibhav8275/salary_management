require "rack/test"
require "stringio"

# Bulk import steps (REQUIREMENTS §3.4 – §3.6, FR-4.1 – FR-4.8, FR-6.1 – FR-6.6,
# BR-5, BR-6, BR-7; LLD §8).
#
# The upload is exercised end to end: the API stages the CSV in the fake bucket
# and enqueues a job, and the scenario then performs that job. Nothing here
# reaches AWS, and no step reads the CSV back out of the bucket directly, so the
# upload-then-read path is genuinely covered.
#
# Row numbers are 1-based and count the header row, so the first data row of a
# CSV is row 2.
Given('a salary CSV file {string} with:') do |filename, table|
  # The feature refers to employees by name for readability; the CSV itself uses
  # employee_id, which is the employee number (LLD §2.1).
  headers = table.headers.map { |header| header == "employee" ? "employee_id" : header }
  rows = table.rows.map do |row|
    row.each_with_index.map do |cell, index|
      headers[index] == "employee_id" ? employee_id_for_csv(cell) : cell.to_s
    end
  end

  stage_file(filename, to_csv(headers, rows), "text/csv")
end

Given('a salary CSV file {string} with {int} salary rows for {string}') do |filename, count, name|
  employee = employee_named(name)
  headers = %w[employee_id effective_date base_salary bonus allowance]
  # Distinct, ascending effective dates so every row opens a new salary period
  # rather than being rejected as stale.
  first_date = Date.new(2000, 1, 1)
  rows = count.times.map do |index|
    [ employee.id, (first_date + (index * 7)).iso8601, 50_000 + index, 0, 0 ]
  end

  stage_file(filename, to_csv(headers, rows), "text/csv")
end

Given('a non-CSV file {string} with content {string}') do |filename, content|
  stage_file(
    filename,
    content,
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
  )
end

When("the HR Manager uploads the salary CSV {string}") do |filename|
  file = staged_file(filename)
  upload = Rack::Test::UploadedFile.new(
    StringIO.new(file[:content]),
    file[:content_type],
    original_filename: filename
  )

  post "/api/v1/salary-imports", params: { file: upload }
  capture_import_from_response
end

When("the HR Manager processes the import") do
  run_import_job(last_import!)
end

When("the HR Manager lists salary imports") do
  get "/api/v1/salary-imports"
end

When("the HR Manager opens the most recent import") do
  @last_import = SalaryImport.order(:id).last
  get "/api/v1/salary-imports/#{@last_import.id}"
end

Given('a completed import for {string}') do |filename|
  @last_import = create(:salary_import, :completed, filename: filename)
end

Given('a pending import for {string}') do |filename|
  create(:salary_import, filename: filename)
end

Then("the import should be recorded with status {string}") do |status|
  expect(last_import!.reload.status).to eq(status)
end

Then("the import should record the filename {string}") do |filename|
  expect(last_import!.filename).to eq(filename)
end

Then("the import should record the uploading user") do
  expect(last_import!.created_by).to be_present
end

Then("the import should reference an uploaded file") do
  import = last_import!
  expect(import.s3_object_key).to be_present
  expect(fake_s3_bucket.objects).to have_key(import.s3_object_key),
                                       "the CSV was never written to the bucket"
end

Then("a salary import job should be enqueued for the import") do
  expect(jobs_for("SalaryImportJob").size).to eq(1)
end

Then("the job should be enqueued with only the import id") do
  job = jobs_for("SalaryImportJob").first
  raise "expected a SalaryImportJob to be enqueued" if job.nil?

  # LLD §8.1 — nothing about the file travels in the job payload, so the only
  # argument is the import id.
  expect(job[:args]).to eq([ last_import!.id ])
end

Then(/^the import should record (\d+) total, (\d+) processed and (\d+) failed rows?$/) do |total, processed, failed|
  import = last_import!.reload
  counters = [ import.total_records, import.processed_records, import.failed_records ]

  expect(counters).to eq([ total.to_i, processed.to_i, failed.to_i ])
end

Then(/^the import should have (\d+) failed rows?$/) do |count|
  expect(last_import!.reload.failed_records).to eq(count.to_i)
end

Then("the import should have a start timestamp") do
  expect(last_import!.reload.started_at).to be_present
end

Then("the import should have a completion timestamp") do
  import = last_import!
  # LLD §2.6 has no completed_at column, so completion is inferred from a
  # terminal status plus a completion time later than the start.
  expect(import.status).to be_in(%w[completed completed_with_errors failed])
  expect(import.updated_at).to be >= import.started_at
end

Then(/^row (\d+) should be reported as skipped$/) do |row_number|
  error = import_error_for(row_number.to_i)
  raise "expected row #{row_number} to be reported, but no error was recorded" if error.nil?

  expect(error.error_message).to be_present
end

Then(/^row (\d+) should be reported as failed with a message mentioning "([^"]*)"$/) do |row_number, text|
  error = import_error_for(row_number.to_i)
  raise "expected row #{row_number} to be reported, but no error was recorded" if error.nil?

  expect(error.error_message.downcase).to include(text.downcase)
end

Then("the rejected row should record the original row data") do
  error = last_import!.salary_import_errors.first
  raise "expected the import to have recorded a rejected row" if error.nil?

  expect(error.raw_data).to be_present
  expect(error.raw_data.to_s).to include("not-a-date")
end

Then("no salary import should have been created") do
  expect(SalaryImport.count).to eq(0)
end

Then("the import list should contain {int} imports") do |count|
  expect(api_data.size).to eq(count)
end

Then('the import list should include an import with status {string}') do |status|
  expect(api_data.map { |row| row["status"] }).to include(status)
end

module ImportStepHelpers
  def to_csv(headers, rows)
    ([ headers ] + rows).map { |line| line.join(",") }.join("\n") + "\n"
  end

  # Unknown names resolve to an id that cannot exist, so a scenario can express
  # "a row for an employee who does not exist" without special-casing.
  def employee_id_for_csv(cell)
    name = cell.to_s.strip
    first, last = name.split(/\s+/, 2)
    Employee.find_by(first_name: first, last_name: last)&.id || 999_999
  end

  def import_id_from_response
    body = api_json
    return nil unless body.is_a?(Hash)

    data = body["data"]
    [ body["id"], body["import_id"], data.is_a?(Hash) ? data["id"] : nil ].compact.first
  end

  def capture_import_from_response
    id = import_id_from_response
    @last_import = id ? SalaryImport.find_by(id: id) : nil
  end
end

World(ImportStepHelpers)
