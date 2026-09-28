require "rails_helper"

# LLD §8.4 — every row from any source is validated before it reaches the salary
# rules. A row that cannot be trusted is recorded as an import error rather than
# aborting the file.
#
# The class name is not specified in the LLD; `CsvRowValidator` is the name these
# examples assume, and it is described by string so the missing constant does not
# break suite loading.
RSpec.describe "CsvRowValidator", type: :service do
  let(:validator) { CsvRowValidator.new }
  let(:employee) { create(:employee) }

  def valid_row(overrides = {})
    {
      "employee_id" => employee.id.to_s,
      "effective_date" => "2026-01-01",
      "base_salary" => "60000",
      "bonus" => "0",
      "allowance" => "0"
    }.merge(overrides)
  end

  describe "a well formed row" do
    it "is valid" do
      expect(validator.valid?(valid_row)).to be(true)
    end

    it "exposes the parsed values" do
      result = validator.validate(valid_row)

      expect(result).to be_valid
      expect(result.employee).to eq(employee)
      expect(result.base_salary).to eq(BigDecimal("60000.0"))
      expect(result.bonus).to eq(BigDecimal("0"))
      expect(result.allowance).to eq(BigDecimal("0"))
      expect(result.effective_date).to eq(Date.new(2026, 1, 1))
    end

    it "keeps the original row for the error report" do
      result = validator.validate(valid_row)

      expect(result.raw_data).to eq(valid_row)
    end
  end

  describe "the employee" do
    it "rejects an unknown employee id" do
      expect(validator.validate(valid_row("employee_id" => "999999"))).not_to be_valid
    end

    it "rejects a missing employee id" do
      expect(validator.validate(valid_row("employee_id" => ""))).not_to be_valid
    end

    it "mentions the unknown id in the message" do
      result = validator.validate(valid_row("employee_id" => "999999"))

      expect(result.error_message).to include("999999")
    end
  end

  describe "the effective date" do
    it "rejects a malformed date" do
      expect(validator.validate(valid_row("effective_date" => "not-a-date"))).not_to be_valid
    end

    it "rejects a missing date" do
      expect(validator.validate(valid_row("effective_date" => ""))).not_to be_valid
    end

    it "rejects an impossible date" do
      expect(validator.validate(valid_row("effective_date" => "2026-02-30"))).not_to be_valid
    end
  end

  describe "the amounts" do
    it "rejects a non numeric base salary" do
      expect(validator.validate(valid_row("base_salary" => "abc"))).not_to be_valid
    end

    it "rejects a negative base salary" do
      expect(validator.validate(valid_row("base_salary" => "-1"))).not_to be_valid
    end

    it "rejects a negative bonus" do
      expect(validator.validate(valid_row("bonus" => "-1"))).not_to be_valid
    end

    it "rejects a negative allowance" do
      expect(validator.validate(valid_row("allowance" => "-1"))).not_to be_valid
    end

    it "rejects a missing base salary" do
      expect(validator.validate(valid_row("base_salary" => ""))).not_to be_valid
    end

    it "accepts a decimal amount" do
      result = validator.validate(valid_row("base_salary" => "60000.55"))

      expect(result).to be_valid
      expect(result.base_salary).to eq(BigDecimal("60000.55"))
    end

    # The header is fixed, but a bonus or allowance column is commonly absent
    # from an export and should default to zero rather than fail the row.
    it "defaults a missing bonus to zero" do
      row = valid_row
      row.delete("bonus")

      expect(validator.validate(row).bonus).to eq(BigDecimal("0"))
    end

    it "defaults a missing allowance to zero" do
      row = valid_row
      row.delete("allowance")

      expect(validator.validate(row).allowance).to eq(BigDecimal("0"))
    end
  end

  describe "the header" do
    it "rejects a file without the required columns" do
      expect(validator.valid_headers?(%w[employee_id effective_date])).to be(false)
    end

    it "accepts the documented header" do
      expect(validator.valid_headers?(%w[employee_id effective_date base_salary bonus allowance])).to be(true)
    end
  end
end
