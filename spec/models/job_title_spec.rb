require "rails_helper"

# LLD §2.9 — a job title is reference data an employee belongs to, like a
# department, but the role is only ever typed free-form in the CSV. The model's
# two rules — normalize before validate, uniqueness ignoring case — are what
# turn "Senior software engineer", "Senior Software  Engineer" and "SENIOR
# SOFTWARE ENGINEER" into one row, so a title-based report counts them once.
RSpec.describe JobTitle, type: :model do
  # `build` rather than `create`: these examples are about validation, so nothing
  # should reach the database.
  def job_title(overrides = {})
    build(:job_title, { title: "Software Engineer" }.merge(overrides))
  end

  describe "normalization" do
    # LLD §2.9 — one canonical spelling per role. The whitespace is collapsed
    # before validation, so a value cannot be stored with stray spacing.
    it "strips surrounding whitespace" do
      expect(job_title(title: "  Software Engineer  ").tap(&:valid?).title).to eq("Software Engineer")
    end

    it "collapses interior spaces" do
      expect(job_title(title: "Senior   Software   Engineer").tap(&:valid?).title).to eq("Senior Software Engineer")
    end

    it "does not alter a canonical title" do
      expect(job_title.title).to eq("Software Engineer")
    end
  end

  describe "validations" do
    it "is valid with a title" do
      expect(job_title).to be_valid
    end

    it "requires a title" do
      record = job_title(title: nil)

      expect(record).not_to be_valid
      expect(record.errors[:title]).to be_present
    end

    it "rejects a blank title" do
      # A whitespace-only value is not a role for an employee to belong to.
      expect(job_title(title: "   ")).not_to be_valid
    end

    it "rejects a duplicate title" do
      create(:job_title, title: "Software Engineer")

      expect(job_title).not_to be_valid
    end

    # LLD §2.9 — the whole reason titles are reference data: a role cannot exist
    # under two spellings, so the same title in a different case is a duplicate.
    it "rejects a duplicate title that differs only by case" do
      create(:job_title, title: "Software Engineer")

      expect(job_title(title: "SOFTWARE ENGINEER")).not_to be_valid
      expect(job_title(title: "software engineer")).not_to be_valid
    end
  end

  describe "associations" do
    it "has many employees" do
      expect(described_class.reflect_on_association(:employees)&.macro).to eq(:has_many)
    end
  end

  describe "reporting" do
    # LLD §2.9 — grouping by the association joins an employee back to their
    # role, which is what a title-based report ("average salary for Software
    # Engineer") would be built on.
    it "finds the employees in a title" do
      title = ReferenceData.job_title("Software Engineer")
      create(:employee)
      create(:employee)

      expect(Employee.joins(:job_title).where(job_titles: { title: title.title }).count).to eq(2)
    end
  end
end
