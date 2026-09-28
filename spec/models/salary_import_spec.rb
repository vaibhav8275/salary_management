require "rails_helper"

# LLD §8.2 — the import status is a Rails enum backed by an integer column.
# The stored values are part of the schema, so these examples pin the numbers as
# well as the names: renumbering them would silently reinterpret existing rows.
RSpec.describe SalaryImport, type: :model do
  describe "the status enum" do
    {
      "pending" => 0,
      "processing" => 1,
      "completed" => 2,
      "completed_with_errors" => 3,
      "failed" => 4
    }.each do |name, value|
      it "stores #{name} as #{value}" do
        expect(described_class.statuses).to include(name => value)

        record = create(:salary_import, status: name)

        expect(record.reload.status).to eq(name)
        expect(raw_status_of(record)).to eq(value)
      end
    end

    it "rejects a status outside the enum" do
      expect { create(:salary_import, status: :archived) }.to raise_error(ArgumentError)
    end
  end

  # Rails casts an enum attribute on every read, including `read_attribute`, so
  # the stored integer is only visible in the database.
  def raw_status_of(record)
    ActiveRecord::Base.connection.select_value(
      ActiveRecord::Base.sanitize_sql_array(
        [ "SELECT status FROM salary_imports WHERE id = ?", record.id ]
      )
    )
  end

  describe "the status values" do
    it "exposes exactly the documented statuses" do
      expect(described_class.statuses.keys).to contain_exactly(
        "pending", "processing", "completed", "completed_with_errors", "failed"
      )
    end

    it "defaults to pending" do
      record = described_class.new

      expect(record.status).to eq("pending")
    end
  end

  describe "counters" do
    it "starts at zero" do
      record = create(:salary_import)

      expect(record.total_records).to eq(0)
      expect(record.processed_records).to eq(0)
      expect(record.failed_records).to eq(0)
    end
  end

  describe "associations" do
    it "has many salary import errors" do
      expect(described_class.reflect_on_association(:salary_import_errors)&.macro).to eq(:has_many)
    end

    it "destroys its errors when the import is destroyed" do
      salary_import = create(:salary_import)
      create(:salary_import_error, salary_import: salary_import, row_number: 2)

      salary_import.destroy!

      expect(SalaryImportError.count).to eq(0)
    end
  end
end
