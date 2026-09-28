require "rails_helper"

# LLD §2.1 — employees own the identity attributes. A department, a job title
# and a country are foreign keys into reference data rather than free-text
# columns, and the employee's salary currency is reached through their country
# (§2.3), so an employee has no currency of their own to validate.
RSpec.describe Employee, type: :model do
  # `build` rather than `create`: these examples are about validation, so nothing
  # should reach the database. The factory supplies the department, title and country.
  def employee(overrides = {})
    build(
      :employee,
      {
        first_name: "Ada",
        last_name: "Lovelace",
        email: "ada@example.com",
        department: ReferenceData.department("Engineering"),
        job_title: ReferenceData.job_title("Software Engineer"),
        country: ReferenceData.country("United Kingdom", "GBP"),
        hire_date: Date.new(2019, 3, 1)
      }.merge(overrides)
    )
  end

  describe "validations" do
    it "is valid with every required attribute" do
      expect(employee).to be_valid
    end

    %i[first_name last_name email department job_title country hire_date].each do |attribute|
      it "requires #{attribute}" do
        record = employee(attribute => nil)

        expect(record).not_to be_valid
        expect(record.errors[attribute]).to be_present
      end
    end

    it "rejects a duplicate email" do
      create(:employee, email: "ada@example.com")

      expect(employee).not_to be_valid
    end

    it "keeps case sensitive emails distinct at the application level" do
      # The index is byte-for-byte unique, so the database allows both. This
      # example documents that behaviour instead of asserting a rule the schema
      # does not enforce.
      create(:employee, email: "ada@example.com")

      expect(employee(email: "ADA@example.com")).to be_valid
    end
  end

  describe "associations" do
    it "belongs to a department" do
      expect(described_class.reflect_on_association(:department)&.macro).to eq(:belongs_to)
    end

    it "belongs to a country" do
      expect(described_class.reflect_on_association(:country)&.macro).to eq(:belongs_to)
    end

    # LLD §2.9 — every employee sits in a job title, so a title-based report can
    # group the whole directory by role.
    it "belongs to a job title" do
      expect(described_class.reflect_on_association(:job_title)&.macro).to eq(:belongs_to)
    end

    # LLD §2.1 / FR-2.1 — salary records hang off the employee, and the
    # directory never needs a salary record to exist.
    it "has many salary records" do
      expect(described_class.reflect_on_association(:salary_records)&.macro).to eq(:has_many)
    end
  end

  # BR-8, LLD §2.1, §2.3 — the currency is the country's, reached through it.
  describe "currency" do
    it "is the currency of the employee's country" do
      gbp = ReferenceData.currency("GBP")
      record = create(:employee, country: create(:country, name: "United Kingdom", currency: gbp))

      expect(record.currency).to eq(gbp)
      expect(record.country.currency).to eq(gbp)
    end

    it "has no currency column of its own" do
      expect(described_class.column_names).not_to include("currency_id")
    end

    it "reports the currency of the country it is in, not a stored value" do
      # Two employees in the same country share a currency because the country
      # decides it; a stored per-employee currency could disagree.
      country = create(:country, :eur)
      first = create(:employee, country: country)
      second = create(:employee, country: country)

      expect([ first.currency, second.currency ].map(&:code)).to eq(%w[EUR EUR])
    end
  end
end
