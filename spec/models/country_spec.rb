require "rails_helper"

# LLD §2.3 — a country is reference data and it owns the currency salaries in that
# country are paid in. One row per country, one currency per country, name unique.
RSpec.describe Country, type: :model do
  # `build` rather than `create`: these examples are about validation, so nothing
  # should reach the database. The currency comes from the reference data the
  # documented scenarios use.
  def country(overrides = {})
    build(
      :country,
      {
        name: "United Kingdom",
        currency: ReferenceData.currency("GBP")
      }.merge(overrides)
    )
  end

  describe "validations" do
    it "is valid with a name and a currency" do
      expect(country).to be_valid
    end

    it "requires a name" do
      record = country(name: nil)

      expect(record).not_to be_valid
      expect(record.errors[:name]).to be_present
    end

    # BR-8, LLD §2.3 — a country without a currency would leave every employee in
    # it without a currency for their salary.
    it "requires a currency" do
      record = country(currency: nil)

      expect(record).not_to be_valid
      expect(record.errors[:currency]).to be_present
    end

    # LLD §2.3 — a duplicated name would split a report in two.
    it "rejects a duplicate name" do
      create(:country, name: "United Kingdom")

      expect(country).not_to be_valid
    end
  end

  describe "associations" do
    it "belongs to a currency" do
      expect(described_class.reflect_on_association(:currency)&.macro).to eq(:belongs_to)
    end

    it "has many employees" do
      expect(described_class.reflect_on_association(:employees)&.macro).to eq(:has_many)
    end
  end

  # BR-8, LLD §2.3 — the country is the whole reason an employee's salary has a
  # currency, so the currency is exactly one row shared by everyone in the country.
  describe "currency" do
    it "is the currency every employee in it is paid in" do
      gbp = ReferenceData.currency("GBP")
      record = create(:country, :gbp)
      employees = create_list(:employee, 2, country: record)

      expect(employees.map { |employee| employee.currency }).to all(eq(gbp))
    end
  end
end
