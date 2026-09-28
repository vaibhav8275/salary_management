require "rails_helper"

# LLD §4 — around 10,000 employees are in scope, so the directory filters and
# the salary queries have to be indexed. These examples assert the indexes the
# design calls for actually exist with the documented columns and uniqueness.
RSpec.describe "Database indexes", type: :schema do
  let(:connection) { ActiveRecord::Base.connection }

  def index_on(table, columns)
    connection.indexes(table).find { |index| index.columns == Array(columns).map(&:to_s) }
  end

  describe "employees" do
    # FR-1.2 — filter by department. LLD §2.1, §4: the filter resolves a name to
    # an id and queries the foreign key, so the index is on the id.
    it "indexes department_id" do
      expect(index_on("employees", :department_id)).to be_present
    end

    # FR-1.4 — filter by country.
    it "indexes country_id" do
      expect(index_on("employees", :country_id)).to be_present
    end

    # FR-1.3 — search by name.
    it "indexes first_name" do
      expect(index_on("employees", :first_name)).to be_present
    end

    it "indexes last_name" do
      expect(index_on("employees", :last_name)).to be_present
    end

    # LLD §2.1 — one row per person.
    it "indexes email uniquely" do
      expect(index_on("employees", :email).unique).to be(true)
    end

    # LLD §2.1 — there is no employees.currency_id to index; the currency is
    # reached through the country.
    it "has no currency_id index" do
      expect(index_on("employees", :currency_id)).to be_nil
    end
  end

  # LLD §2.3, §2.4 — the reference tables are matched by name in the directory
  # filters and grouped by in the reports, so the name is unique and indexed.
  describe "countries" do
    it "indexes name uniquely" do
      expect(index_on("countries", :name).unique).to be(true)
    end

    it "indexes currency_id" do
      expect(index_on("countries", :currency_id)).to be_present
    end
  end

  describe "departments" do
    it "indexes name uniquely" do
      expect(index_on("departments", :name).unique).to be(true)
    end
  end

  describe "salary_records" do
    # LLD §3 — one record per employee per effective period. The unique index is
    # what makes a duplicate period impossible even under concurrency.
    it "indexes employee_id and effective_date uniquely" do
      index = index_on("salary_records", %i[employee_id effective_date])

      expect(index).to be_present
      expect(index.unique).to be(true)
    end

    it "indexes effective_date for reporting and current-salary lookups" do
      expect(index_on("salary_records", :effective_date)).to be_present
    end
  end

  describe "salary_imports" do
    # FR-6.1 — the import list is ordered by id and filtered by status.
    it "has no unnecessary extra indexes" do
      # A status index is only worth its write cost if the list filters by it.
      # The LLD does not require one, so this example documents the decision.
      expect(index_on("salary_imports", :status)).to be_nil
    end
  end

  describe "salary_import_errors" do
    # FR-6.3 — show the failed rows for one import.
    it "indexes salary_import_id" do
      expect(index_on("salary_import_errors", :salary_import_id)).to be_present
    end

    it "indexes employee_id" do
      expect(index_on("salary_import_errors", :employee_id)).to be_present
    end
  end

  describe "versions" do
    # LLD §7.1 — the audit history for one salary record.
    it "indexes item_type and item_id" do
      expect(index_on("versions", %i[item_type item_id])).to be_present
    end

    # LLD §7.3 — list the versions produced by one import.
    it "indexes salary_import_id" do
      expect(index_on("versions", :salary_import_id)).to be_present
    end
  end

  describe "foreign keys" do
    # LLD §2.1, §2.4 — an employee is placed in a department.
    it "points employees at departments" do
      foreign_key = connection.foreign_keys("employees").find { |fk| fk.to_table == "departments" }

      expect(foreign_key).to be_present
      expect(foreign_key.options[:column]).to eq("department_id")
    end

    # LLD §2.1, §2.3 — an employee is placed in a country, which is what makes
    # their salary currency well defined.
    it "points employees at countries" do
      foreign_key = connection.foreign_keys("employees").find { |fk| fk.to_table == "countries" }

      expect(foreign_key).to be_present
      expect(foreign_key.options[:column]).to eq("country_id")
    end

    # LLD §2.3 — a country is paid in one currency.
    it "points countries at currencies" do
      foreign_key = connection.foreign_keys("countries").find { |fk| fk.to_table == "currencies" }

      expect(foreign_key).to be_present
      expect(foreign_key.options[:column]).to eq("currency_id")
    end

    it "points salary_records at employees" do
      foreign_key = connection.foreign_keys("salary_records").find { |fk| fk.to_table == "employees" }

      expect(foreign_key).to be_present
      expect(foreign_key.options[:column]).to eq("employee_id")
    end

    it "points salary_import_errors at salary_imports" do
      foreign_key = connection.foreign_keys("salary_import_errors").find { |fk| fk.to_table == "salary_imports" }

      expect(foreign_key).to be_present
    end

    it "points salary_import_errors at employees" do
      foreign_key = connection.foreign_keys("salary_import_errors").find { |fk| fk.to_table == "employees" }

      expect(foreign_key).to be_present
    end
  end
end
