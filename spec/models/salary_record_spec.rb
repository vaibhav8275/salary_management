require "rails_helper"

# LLD §3 — a salary record is one effective period for one employee.
# `base_salary`, `bonus` and `allowance` are non-negative (BR-1), and the
# database holds a unique index on employee + effective_date.
RSpec.describe SalaryRecord, type: :model do
  let(:employee) { create(:employee) }

  describe "validations" do
    it "is valid with a non-negative amount for every component" do
      record = SalaryRecord.new(
        employee: employee,
        base_salary: 50_000,
        bonus: 1_000,
        allowance: 250,
        effective_date: Date.new(2025, 1, 1)
      )

      expect(record).to be_valid
    end

    it "requires an employee" do
      record = SalaryRecord.new(
        employee: nil,
        base_salary: 50_000,
        bonus: 0,
        allowance: 0,
        effective_date: Date.new(2025, 1, 1)
      )

      expect(record).not_to be_valid
      expect(record.errors[:employee]).to be_present
    end

    it "requires an effective date" do
      record = SalaryRecord.new(
        employee: employee,
        base_salary: 50_000,
        bonus: 0,
        allowance: 0,
        effective_date: nil
      )

      expect(record).not_to be_valid
      expect(record.errors[:effective_date]).to be_present
    end

    # BR-1 — amounts are never negative. The check constraints are the last
    # line of defence; these examples pin the model level messages that
    # SalaryService relies on to return 422 instead of raising.
    { base_salary: -1, bonus: 0, allowance: 0 }.each do |attribute, value|
      it "rejects a negative #{attribute}" do
        record = SalaryRecord.new(
          employee: employee,
          base_salary: 50_000,
          bonus: 0,
          allowance: 0,
          effective_date: Date.new(2025, 1, 1)
        )
        record.public_send("#{attribute}=", value)

        expect(record).not_to be_valid
        expect(record.errors[attribute]).to be_present
      end
    end

    it "rejects a negative allowance" do
      record = SalaryRecord.new(
        employee: employee,
        base_salary: 50_000,
        bonus: 0,
        allowance: -1,
        effective_date: Date.new(2025, 1, 1)
      )

      expect(record).not_to be_valid
      expect(record.errors[:allowance]).to be_present
    end
  end

  describe "uniqueness of the effective period" do
    it "refuses a second record for the same employee and effective date" do
      create(:salary_record, employee: employee, effective_date: Date.new(2025, 1, 1))
      duplicate = SalaryRecord.new(
        employee: employee,
        base_salary: 60_000,
        bonus: 0,
        allowance: 0,
        effective_date: Date.new(2025, 1, 1)
      )

      expect(duplicate).not_to be_valid
    end

    it "allows the same effective date for a different employee" do
      create(:salary_record, employee: employee, effective_date: Date.new(2025, 1, 1))
      other = SalaryRecord.new(
        employee: create(:employee),
        base_salary: 60_000,
        bonus: 0,
        allowance: 0,
        effective_date: Date.new(2025, 1, 1)
      )

      expect(other).to be_valid
    end
  end

  describe "amounts" do
    # BR-8 / LLD §2.5 — money is stored as an exact decimal, not a float.
    it "keeps two decimal places" do
      record = create(:salary_record, employee: employee, base_salary: "50000.55")

      expect(record.reload.base_salary).to eq(BigDecimal("50000.55"))
    end
  end

  describe "associations" do
    it "belongs to an employee" do
      expect(described_class.reflect_on_association(:employee)&.macro).to eq(:belongs_to)
    end
  end
end
