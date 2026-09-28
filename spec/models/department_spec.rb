require "rails_helper"

# LLD §2.4 — a department is reference data an employee belongs to. The name is
# unique because the directory filter and the department reports group by it.
RSpec.describe Department, type: :model do
  # `build` rather than `create`: these examples are about validation, so nothing
  # should reach the database.
  def department(overrides = {})
    build(:department, { name: "Engineering" }.merge(overrides))
  end

  describe "validations" do
    it "is valid with a name" do
      expect(department).to be_valid
    end

    it "requires a name" do
      record = department(name: nil)

      expect(record).not_to be_valid
      expect(record.errors[:name]).to be_present
    end

    it "rejects a duplicate name" do
      create(:department, name: "Sales")

      expect(department(name: "Sales")).not_to be_valid
    end

    # LLD §2.4 — departments are data, not free text typed per employee, so a
    # blank or whitespace-only name is not a department.
    it "rejects a blank name" do
      expect(department(name: "  ")).not_to be_valid
    end
  end

  describe "associations" do
    it "has many employees" do
      expect(described_class.reflect_on_association(:employees)&.macro).to eq(:has_many)
    end
  end
end
