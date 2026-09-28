require "rails_helper"

# LLD §2.2 — currencies are reference data. `code` is an ISO 4217 code, unique
# and limited to three characters; `name` and `symbol` are required.
RSpec.describe Currency, type: :model do
  def currency(overrides = {})
    described_class.new({ code: "USD", name: "US Dollar", symbol: "$" }.merge(overrides))
  end

  describe "validations" do
    it "is valid with a code, name and symbol" do
      expect(currency).to be_valid
    end

    it "requires a code" do
      record = currency(code: nil)

      expect(record).not_to be_valid
      expect(record.errors[:code]).to be_present
    end

    it "requires a name" do
      record = currency(name: nil)

      expect(record).not_to be_valid
      expect(record.errors[:name]).to be_present
    end

    it "requires a symbol" do
      record = currency(symbol: nil)

      expect(record).not_to be_valid
      expect(record.errors[:symbol]).to be_present
    end
  end

  describe "associations" do
    # LLD §2.2, §2.3 — countries reference a currency, not employees, and a
    # currency is not removed while countries still use it.
    it "has many countries" do
      expect(described_class.reflect_on_association(:countries)&.macro).to eq(:has_many)
    end

    it "has the countries that use it" do
      currency = create(:currency)
      country = create(:country, currency: currency)

      expect(currency.countries).to contain_exactly(country)
    end

    it "is not destroyed while a country uses it" do
      currency = create(:currency)
      create(:country, currency: currency)

      expect(currency.destroy).to be(false)
      expect(described_class.exists?(currency.id)).to be(true)
    end

    it "is destroyed when no country uses it" do
      currency = create(:currency)

      expect(currency.destroy).to be_truthy
      expect(described_class.exists?(currency.id)).to be(false)
    end
  end
end
