require "rails_helper"

# LLD §3 — the database is the last line of defence. Model validations are
# covered in spec/models; these examples prove the constraints themselves exist
# and reject bad data even when the model layer is bypassed entirely.
RSpec.describe "Database constraints", type: :schema do
  let(:connection) { ActiveRecord::Base.connection }

  # Raw inserts so nothing in the model layer can mask a missing constraint.
  def insert_row(table, attributes)
    columns = attributes.keys
    values = attributes.values

    connection.insert(
      ActiveRecord::Base.sanitize_sql_array(
        [ "INSERT INTO #{table} (#{columns.join(', ')}) VALUES (#{Array.new(columns.size, '?').join(', ')})", *values ]
      )
    )
  end

  def timestamps
    { created_at: Time.current, updated_at: Time.current }
  end

  # `salary_import_errors` and `versions` have no updated_at column.
  def created_at_only
    { created_at: Time.current }
  end

  # These examples insert rows by hand, so they cannot use the `:employee`
  # factory: the factory saves a row, and here the point is what the database
  # says about a row the model layer never touched. The unique email still has to
  # differ between two inserts in one example, hence the per-example counter.
  # The department and country rows themselves are saved by the factories — the
  # foreign key is what is under test here, not their creation.
  before { @probe = 0 }

  def valid_employee_row(overrides = {})
    @probe += 1

    {
      first_name: "Ada",
      last_name: "Lovelace",
      email: "constraint-probe-#{@probe}@example.com",
      department_id: ReferenceData.department("Engineering").id,
      job_title_id: ReferenceData.job_title("Software Engineer").id,
      country_id: ReferenceData.country("United Kingdom", "GBP").id,
      hire_date: Date.new(2019, 3, 1)
    }.merge(timestamps).merge(overrides)
  end

  def valid_salary_row(overrides = {})
    employee = create(:employee)

    {
      employee_id: employee.id,
      base_salary: 50_000,
      bonus: 0,
      allowance: 0,
      effective_date: Date.new(2025, 1, 1)
    }.merge(timestamps).merge(overrides)
  end

  describe "employees" do
    %i[first_name last_name email department_id job_title_id country_id hire_date].each do |column|
      it "rejects a null #{column}" do
        expect { insert_row("employees", valid_employee_row(column => nil)) }
          .to raise_error(ActiveRecord::NotNullViolation)
      end
    end

    it "rejects a duplicate email" do
      create(:employee, email: "duplicate@example.com")

      expect { insert_row("employees", valid_employee_row(email: "duplicate@example.com")) }
        .to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "rejects a country_id that does not exist" do
      expect { insert_row("employees", valid_employee_row(country_id: 0)) }
        .to raise_error(ActiveRecord::InvalidForeignKey)
    end

    it "rejects a department_id that does not exist" do
      expect { insert_row("employees", valid_employee_row(department_id: 0)) }
        .to raise_error(ActiveRecord::InvalidForeignKey)
    end

    it "rejects a job_title_id that does not exist" do
      expect { insert_row("employees", valid_employee_row(job_title_id: 0)) }
        .to raise_error(ActiveRecord::InvalidForeignKey)
    end

    # LLD §2.1 — the employee's currency is the country's, so there is no
    # `employees.currency_id` column left to fill in or contradict.
    it "has no currency_id column" do
      expect(connection.columns("employees").map(&:name)).not_to include("currency_id")
    end
  end

  # LLD §2.3, §2.4 — the reference tables are small, but the uniqueness that
  # keeps a report from splitting in two is enforced here, not in application code.
  describe "countries" do
    def valid_country_row(overrides = {})
      { name: "United Kingdom", currency_id: ReferenceData.currency("GBP").id }.merge(timestamps).merge(overrides)
    end

    it "rejects a null name" do
      expect { insert_row("countries", valid_country_row(name: nil)) }
        .to raise_error(ActiveRecord::NotNullViolation)
    end

    it "rejects a null currency_id" do
      expect { insert_row("countries", valid_country_row(currency_id: nil)) }
        .to raise_error(ActiveRecord::NotNullViolation)
    end

    it "rejects a duplicate name" do
      create(:country, name: "United Kingdom")

      expect { insert_row("countries", valid_country_row) }
        .to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "rejects a currency_id that does not exist" do
      expect { insert_row("countries", valid_country_row(currency_id: 0)) }
        .to raise_error(ActiveRecord::InvalidForeignKey)
    end
  end

  describe "departments" do
    def valid_department_row(overrides = {})
      { name: "Engineering" }.merge(timestamps).merge(overrides)
    end

    it "rejects a null name" do
      expect { insert_row("departments", valid_department_row(name: nil)) }
        .to raise_error(ActiveRecord::NotNullViolation)
    end

    it "rejects a duplicate name" do
      create(:department, name: "Sales")

      expect { insert_row("departments", valid_department_row(name: "Sales")) }
        .to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe "job_titles" do
    def valid_job_title_row(overrides = {})
      { title: "Software Engineer" }.merge(timestamps).merge(overrides)
    end

    it "rejects a null title" do
      expect { insert_row("job_titles", valid_job_title_row(title: nil)) }
        .to raise_error(ActiveRecord::NotNullViolation)
    end

    # There is no database-level unique constraint on job_titles.title because
    # the uniqueness is case-insensitive and enforced by the model (see
    # app/models/job_title.rb). The database allows duplicates to be inserted
    # via raw SQL, but the model validation will prevent saving a duplicate.
    it "does not reject a duplicate title at the database level" do
      create(:job_title, title: "Software Engineer")

      expect { insert_row("job_titles", valid_job_title_row) }
        .not_to raise_error
    end
  end

  describe "salary_records" do
    it "rejects a null effective_date" do
      expect { insert_row("salary_records", valid_salary_row(effective_date: nil)) }
        .to raise_error(ActiveRecord::NotNullViolation)
    end

    it "rejects a null base_salary" do
      expect { insert_row("salary_records", valid_salary_row(base_salary: nil)) }
        .to raise_error(ActiveRecord::NotNullViolation)
    end

    # BR-1 — no negative money, enforced in the database.
    { base_salary: -1, bonus: -1, allowance: -1 }.each do |column, value|
      it "rejects a negative #{column}" do
        expect { insert_row("salary_records", valid_salary_row(column => value)) }
          .to raise_error(ActiveRecord::StatementInvalid, /#{column}_non_negative/)
      end
    end

    it "accepts zero amounts" do
      expect { insert_row("salary_records", valid_salary_row(base_salary: 0, bonus: 0, allowance: 0)) }
        .not_to raise_error
    end

    it "rejects a second record for the same employee and effective date" do
      employee = create(:employee)
      create(:salary_record, employee: employee, effective_date: Date.new(2025, 1, 1))

      expect { insert_row("salary_records", valid_salary_row(employee_id: employee.id)) }
        .to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "rejects an employee_id that does not exist" do
      expect { insert_row("salary_records", valid_salary_row(employee_id: 0)) }
        .to raise_error(ActiveRecord::InvalidForeignKey)
    end
  end

  describe "salary_imports" do
    it "rejects a null filename" do
      row = { s3_object_key: "k", status: 0, total_records: 0, processed_records: 0,
              failed_records: 0, created_by: 1 }.merge(timestamps)

      expect { insert_row("salary_imports", row.merge(filename: nil)) }
        .to raise_error(ActiveRecord::NotNullViolation)
    end

    it "rejects a null s3_object_key" do
      row = { filename: "f.csv", status: 0, total_records: 0, processed_records: 0,
              failed_records: 0, created_by: 1 }.merge(timestamps)

      expect { insert_row("salary_imports", row.merge(s3_object_key: nil)) }
        .to raise_error(ActiveRecord::NotNullViolation)
    end

    it "rejects a null created_by" do
      row = { filename: "f.csv", s3_object_key: "k", status: 0, total_records: 0,
              processed_records: 0, failed_records: 0 }.merge(timestamps)

      expect { insert_row("salary_imports", row.merge(created_by: nil)) }
        .to raise_error(ActiveRecord::NotNullViolation)
    end

    it "defaults the status to pending" do
      id = insert_row("salary_imports", { filename: "f.csv", s3_object_key: "k", total_records: 0,
                                          processed_records: 0, failed_records: 0, created_by: 1 }.merge(timestamps))

      expect(SalaryImport.find(id).status).to eq("pending")
    end
  end

  describe "salary_import_errors" do
    let(:salary_import) { create(:salary_import) }

    # `insert_row` bypasses type casting, so jsonb values are written as the
    # JSON text PostgreSQL will parse.
    let(:empty_raw_data) { "{}" }

    it "requires a row number" do
      expect do
        insert_row("salary_import_errors", { salary_import_id: salary_import.id, error_message: "bad", raw_data: empty_raw_data }.merge(created_at_only))
      end.to raise_error(ActiveRecord::NotNullViolation)
    end

    it "requires an error message" do
      expect do
        insert_row("salary_import_errors", { salary_import_id: salary_import.id, row_number: 2, raw_data: empty_raw_data }.merge(created_at_only))
      end.to raise_error(ActiveRecord::NotNullViolation)
    end

    it "requires raw data" do
      expect do
        insert_row("salary_import_errors", { salary_import_id: salary_import.id, row_number: 2, error_message: "bad" }.merge(created_at_only))
      end.to raise_error(ActiveRecord::NotNullViolation)
    end

    # LLD §8.3 — employee_id is nullable so a row naming an unknown employee can
    # still be reported.
    it "accepts a null employee_id" do
      expect do
        insert_row("salary_import_errors", { salary_import_id: salary_import.id, row_number: 2,
                                             error_message: "Unknown employee 999999", raw_data: empty_raw_data }.merge(created_at_only))
      end.not_to raise_error
    end

    it "rejects a salary_import_id that does not exist" do
      expect do
        insert_row("salary_import_errors", { salary_import_id: 0, row_number: 2,
                                             error_message: "bad", raw_data: empty_raw_data }.merge(created_at_only))
      end.to raise_error(ActiveRecord::InvalidForeignKey)
    end
  end

  describe "versions" do
    # LLD §7.2 — a change is either manual or came from a bulk import.
    it "rejects an unknown source" do
      expect do
        insert_row("versions", { item_id: 1, item_type: "SalaryRecord", event: "update",
                                 source: "imported_from_wherever" }.merge(created_at_only))
      end.to raise_error(ActiveRecord::StatementInvalid, /versions_source_check/)
    end

    it "accepts manual" do
      expect do
        insert_row("versions", { item_id: 1, item_type: "SalaryRecord", event: "update",
                                 source: "manual" }.merge(created_at_only))
      end.not_to raise_error
    end

    it "accepts bulk_import" do
      expect do
        insert_row("versions", { item_id: 1, item_type: "SalaryRecord", event: "update",
                                 source: "bulk_import" }.merge(created_at_only))
      end.not_to raise_error
    end

    it "defaults the source to manual" do
      id = insert_row("versions", { item_id: 1, item_type: "SalaryRecord", event: "update" }.merge(created_at_only))

      expect(PaperTrail::Version.find(id).source).to eq("manual")
    end

    # LLD §7.3 — the version points at the import, but deleting the import must
    # not delete the audit trail.
    it "nullifies salary_import_id when the import is deleted" do
      salary_import = create(:salary_import)
      record = as_bulk_import(salary_import) { create(:salary_record, employee: create(:employee)) }
      version_id = latest_version_for(record).id

      salary_import.destroy!

      expect(PaperTrail::Version.find(version_id).salary_import_id).to be_nil
    end
  end
end
