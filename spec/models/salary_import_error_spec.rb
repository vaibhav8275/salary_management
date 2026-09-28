require "rails_helper"

# LLD §8.3 — a row error records the CSV line number, the employee when the row
# could be attributed to one, a message and the raw row. `row_number`,
# `error_message` and `raw_data` are required; `employee_id` is optional because
# an unknown employee id is itself a common error.
RSpec.describe SalaryImportError, type: :model do
  let(:salary_import) { create(:salary_import) }

  describe "validations" do
    it "is valid with an import, a row number, a message and raw data" do
      error = described_class.new(
        salary_import: salary_import,
        row_number: 2,
        employee: create(:employee),
        error_message: "Invalid effective_date",
        raw_data: { "employee_id" => "1" }
      )

      expect(error).to be_valid
    end

    it "is valid without an employee so unknown ids can be reported" do
      error = described_class.new(
        salary_import: salary_import,
        row_number: 2,
        employee: nil,
        error_message: "Unknown employee 999999",
        raw_data: { "employee_id" => "999999" }
      )

      expect(error).to be_valid
    end

    it "requires a salary import" do
      error = described_class.new(
        salary_import: nil,
        row_number: 2,
        error_message: "Invalid row",
        raw_data: {}
      )

      expect(error).not_to be_valid
      expect(error.errors[:salary_import]).to be_present
    end

    it "requires a row number" do
      error = described_class.new(
        salary_import: salary_import,
        row_number: nil,
        error_message: "Invalid row",
        raw_data: {}
      )

      expect(error).not_to be_valid
      expect(error.errors[:row_number]).to be_present
    end

    it "requires an error message" do
      error = described_class.new(
        salary_import: salary_import,
        row_number: 2,
        error_message: nil,
        raw_data: {}
      )

      expect(error).not_to be_valid
      expect(error.errors[:error_message]).to be_present
    end

    it "requires raw data" do
      error = described_class.new(
        salary_import: salary_import,
        row_number: 2,
        error_message: "Invalid row",
        raw_data: nil
      )

      expect(error).not_to be_valid
      expect(error.errors[:raw_data]).to be_present
    end
  end

  describe "associations" do
    it "belongs to a salary import" do
      expect(described_class.reflect_on_association(:salary_import)&.macro).to eq(:belongs_to)
    end

    # The employee is optional, so the association has to allow nil.
    it "belongs to an employee" do
      association = described_class.reflect_on_association(:employee)

      expect(association.macro).to eq(:belongs_to)
      expect(association.options[:optional]).to be(true).or be_nil
    end
  end

  describe "raw data" do
    it "round trips arbitrary CSV columns as a hash" do
      error = create(:salary_import_error,
        salary_import: salary_import,
        row_number: 3,
        raw_data: { "employee_id" => "7", "base_salary" => "60000", "extra" => "kept" }
      )

      expect(error.reload.raw_data).to eq(
        "employee_id" => "7",
        "base_salary" => "60000",
        "extra" => "kept"
      )
    end
  end
end
