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

  describe "the uploaded file" do
    it "reads as a File rather than Csv file in messages" do
      expect(described_class.human_attribute_name(:csv_file)).to eq("File")
    end

    it "accepts a CSV at the size limit" do
      import = build(:salary_import)
      attach_csv(import, "a" * described_class::MAX_FILE_SIZE)

      expect(import).to be_valid
    end

    it "rejects a file over the size limit" do
      import = build(:salary_import)
      attach_csv(import, "a" * (described_class::MAX_FILE_SIZE + 1))

      expect(import).not_to be_valid
      expect(import.errors.full_messages).to include("File size must be 2 MB or smaller")
    end

    # A PDF is both the wrong extension and the wrong content type. Reporting both
    # produced "File must be a CSV file File must have a .csv extension", so the
    # extension answers alone.
    it "reports a wrong extension once, not once per failed check" do
      import = build(:salary_import)
      attach_csv(import, "%PDF-1.7", filename: "salaries.pdf", content_type: "application/pdf")

      expect(import).not_to be_valid
      expect(import.errors.full_messages).to eq([ "File must be a CSV file" ])
    end
  end

  describe "the daily upload limit" do
    # Setup for "this much has already been stored today", so validations are
    # skipped: reaching 60 MB through the per-file limit would mean thirty real
    # uploads per example, and this is a fixture, not a claim about how the
    # allowance was spent.
    def stored_upload_for(user_id, bytes, at: Time.current)
      import = build(:salary_import, created_by: user_id, created_at: at)
      attach_csv(import, "a" * bytes)
      import.save!(validate: false)
      import
    end

    it "is 60 MB" do
      expect(described_class::DAILY_UPLOAD_LIMIT).to eq(60.megabytes)
    end

    it "accepts an upload that lands exactly on the limit" do
      stored_upload_for(hr_manager.id, described_class::DAILY_UPLOAD_LIMIT - 1)
      import = build(:salary_import, created_by: hr_manager.id)
      attach_csv(import, "a")

      expect(import).to be_valid
    end

    it "rejects an upload that would cross the limit" do
      stored_upload_for(hr_manager.id, described_class::DAILY_UPLOAD_LIMIT)
      import = build(:salary_import, created_by: hr_manager.id)
      attach_csv(import, "a")

      expect(import).not_to be_valid
      expect(import.errors.full_messages).to include("File exceeds your daily upload limit of 60 MB")
    end

    it "rejects a file larger than the whole allowance even from nothing used" do
      allow(described_class).to receive(:uploaded_bytes_today).and_return(0)
      import = build(:salary_import, created_by: hr_manager.id)
      attach_csv(import, "a" * (described_class::DAILY_UPLOAD_LIMIT + 1))

      expect(import).not_to be_valid
      expect(import.errors.full_messages).to include("File exceeds your daily upload limit of 60 MB")
    end

    # The point of a per-user ceiling is that it is per user.
    it "counts only the uploading user's own bytes" do
      stored_upload_for(create(:user).id, described_class::DAILY_UPLOAD_LIMIT)
      import = build(:salary_import, created_by: hr_manager.id)
      attach_csv(import, "a")

      expect(import).to be_valid
    end

    describe "the day it counts" do
      it "reports the stored bytes for the day" do
        stored_upload_for(hr_manager.id, 2_048)

        expect(described_class.uploaded_bytes_today(hr_manager.id)).to eq(2_048)
      end

      it "excludes the day before" do
        yesterday = described_class::DAILY_UPLOAD_TIME_ZONE.at(Time.current).beginning_of_day - 1.hour
        stored_upload_for(hr_manager.id, described_class::DAILY_UPLOAD_LIMIT, at: yesterday)

        expect(described_class.uploaded_bytes_today(hr_manager.id)).to eq(0)
      end

      it "excludes the day after" do
        tomorrow = described_class::DAILY_UPLOAD_TIME_ZONE.at(Time.current).beginning_of_day + 1.day
        stored_upload_for(hr_manager.id, described_class::DAILY_UPLOAD_LIMIT, at: tomorrow)

        expect(described_class.uploaded_bytes_today(hr_manager.id)).to eq(0)
      end

      # Six hours into the IST day is 00:30 UTC — the application's own calendar
      # has already rolled over, but this upload belongs to the day still running
      # in IST. A quota cut at UTC midnight would report zero here.
      it "includes the hours IST has but UTC has already rolled past" do
        ist_morning = described_class::DAILY_UPLOAD_TIME_ZONE.at(Time.current).beginning_of_day + 6.hours
        stored_upload_for(hr_manager.id, 1_024, at: ist_morning)

        expect(described_class.uploaded_bytes_today(hr_manager.id)).to eq(1_024)
      end
    end

    # Only a stored upload counts, so a user who picks the wrong file is not
    # charged for it.
    it "does not count an upload that was never saved" do
      rejected = build(:salary_import, created_by: hr_manager.id)
      attach_csv(rejected, "a" * (described_class::MAX_FILE_SIZE + 1))
      rejected.save

      expect(rejected.persisted?).to be(false)
      expect(described_class.uploaded_bytes_today(hr_manager.id)).to eq(0)
    end

    # The worker re-saves the import to record its outcome. Re-checking the quota
    # there would strand an import that was accepted while there was room.
    it "is not re-checked when an accepted import is updated" do
      import = create(:salary_import, created_by: hr_manager.id)
      allow(described_class).to receive(:uploaded_bytes_today).and_return(described_class::DAILY_UPLOAD_LIMIT)

      import.update!(status: :completed, processed_records: 1)

      expect(import.reload.status).to eq("completed")
    end
  end
end
