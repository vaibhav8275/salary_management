class SalaryImport < ApplicationRecord
  # Upper bound for an uploaded CSV. A row is roughly 60 bytes, so
  # this leaves room for a 10,000-employee dataset several times
  # over while still refusing a file large enough to be a mistake or an
  # attempt to exhaust the worker's memory.
  MAX_FILE_SIZE = 2.megabytes

  # What a client may claim the file is. The extension below is the real test;
  # this list exists because the same CSV is labelled `text/csv` by curl and
  # `application/vnd.ms-excel` by older Excel and by some browsers, and rejecting
  # a well-formed CSV on a header it chose is not validation. An empty type is
  # allowed for the same reason: the content itself is parsed and validated
  # before a single row is applied.
  CSV_CONTENT_TYPES = [
    "text/csv",
    "application/csv",
    "text/plain",
    "application/octet-stream",
    "application/vnd.ms-excel"
  ].freeze

  enum :status, {
    pending: 0,
    processing: 1,
    completed: 2,
    completed_with_errors: 3,
    failed: 4
  }

  has_many :salary_import_errors, dependent: :destroy

  # `created_by` is a plain bigint with no foreign key, so the association is
  # declared here rather than inferred. It is optional because the column is
  # populated by the controller, not by devise: an import can outlive the account
  # that uploaded it, and a detail page must not 500 on a missing uploader.
  belongs_to :uploader, class_name: "User", foreign_key: :created_by, optional: true

  # The uploaded CSV is the import's only input, so it belongs to the record
  # rather than beside it: Active Storage stores the file and the metadata, and
  # `purge_later` removes both when the import is destroyed. The blob is uploaded
  # as part of saving, which is why the controller builds the record and its
  # attachment together and lets a validation failure abort both — there is no
  # window in which a file exists in S3 with no import pointing at it.
  has_one_attached :csv_file, dependent: :purge_later

  # `on: :create` because an import is *created* with a CSV, and the file is
  # not a permanent invariant of the record afterwards. Validating presence on
  # every save would mean the worker could not record the outcome of an import
  # whose file had gone missing — the exact case its `rescue` exists to handle.
  validates :csv_file, presence: true, on: :create
  validate :csv_file_size
  validate :csv_file_type

  # The CSV as text, for the worker.
  #
  # `download` is used rather than `blob.open` because the job parses the whole
  # file to decide the row count, and the 2 MB ceiling makes buffering it
  # cheaper than streaming it twice.
  def csv_contents
    csv_file.download
  end

  private

  def csv_file_size
    return unless csv_file.attached?

    errors.add(:csv_file, "must be smaller than #{MAX_FILE_SIZE / 1.megabyte} MB") if csv_file.byte_size > MAX_FILE_SIZE
  end

  def csv_file_type
    return unless csv_file.attached?

    unless csv_file.filename.extension_without_delimiter.casecmp("csv").zero?
      errors.add(:csv_file, "must have a .csv extension")
    end

    content_type = csv_file.content_type.to_s.split(";").first.to_s.strip
    errors.add(:csv_file, "must be a CSV file") if content_type.present? && !CSV_CONTENT_TYPES.include?(content_type)
  end
end
