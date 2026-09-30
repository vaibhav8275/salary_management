# Attachments are files, not rows.
#
# An example's database work is rolled back when it ends, but the CSV it
# uploaded is a real file in the test environment's disk service
# (config/storage.yml `test:`) and a real blob row. Left alone, a run leaves a
# directory of CSVs in tmp/storage and a pile of rows that point at files which
# no longer correspond to anything, so both go.
#
# RSpec runs this once for the suite (nothing in the middle of a run needs a
# file from an earlier example) and Cucumber runs it per scenario, because a
# scenario is allowed to look at what it left behind.
module ActiveStorageHelpers
  # Also available as a module function: RSpec's `after(:suite)` runs outside any
  # example group, so there is no example for the instance method to run on.
  def self.purge_test_blobs!
    ActiveStorage::Blob.unattached.destroy_all
  end

  def purge_test_blobs!
    ActiveStorageHelpers.purge_test_blobs!
  end

  # Stages a CSV on an import, the way an upload would.
  def attach_csv(import, body, filename: "salaries.csv", content_type: "text/csv")
    import.csv_file.attach(io: StringIO.new(body), filename: filename, content_type: content_type)
  end
end
