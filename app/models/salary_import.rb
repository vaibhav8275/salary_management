class SalaryImport < ApplicationRecord
  # Upper bound for an uploaded CSV. A row is roughly 60 bytes, so
  # this leaves room for a 10,000-employee dataset several times
  # over while still refusing a file large enough to be a mistake or an
  # attempt to exhaust the worker's memory.
  MAX_FILE_SIZE = 2.megabytes

  # Ceiling on the bytes one user may store in a day. At the per-file limit above
  # this is thirty uploads, which is generous for a 10,000-employee dataset and
  # still bounds what one account can push through the queue and onto disk.
  DAILY_UPLOAD_LIMIT = 60.megabytes

  # Quota days are cut in IST, not UTC. The application runs in UTC, so this
  # constant is the only place the offset lives — without it the allowance would
  # reset at 05:30 IST, which is not a day boundary anyone thinks in.
  DAILY_UPLOAD_TIME_ZONE = ActiveSupport::TimeZone["Asia/Kolkata"]

  # The attribute is `csv_file` but the person reading the sentence is looking at
  # a file picker, so "Csv file must be a CSV file" is replaced with "File must
  # be a CSV file". Every message below reads through this.
  def self.human_attribute_name(attribute, options = {})
    return "File" if attribute.to_s == "csv_file"

    super
  end

  # Bytes this user has already stored today, counted in IST.
  #
  # Summed from the stored blobs rather than kept as a running counter, so the
  # figure cannot drift from the files actually on disk and nothing has to be
  # reset at midnight. A rejected upload leaves neither an import row nor a blob,
  # so it costs the user nothing — picking the wrong file is not penalised.
  def self.uploaded_bytes_today(user_id, now: Time.current)
    window_start = DAILY_UPLOAD_TIME_ZONE.at(now).beginning_of_day

    joins(csv_file_attachment: :blob)
      .where(created_by: user_id, created_at: window_start...(window_start + 1.day))
      .sum(Arel.sql("active_storage_blobs.byte_size"))
  end

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

  # `created_by` is the foreign key to the uploading account. It is required:
  # the column is NOT NULL and the database enforces the reference, so an import
  # cannot exist without an uploader. The controller sets it from the
  # authenticated user at creation time.
  belongs_to :uploader, class_name: "User", foreign_key: :created_by

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

  # `on: :create` for the same reason as the presence check above: the quota is
  # spent at upload time. Re-saving an import to record its outcome must not
  # re-validate the day's bytes, or the worker could not finish an import that
  # was legitimately accepted when the day's allowance was still there.
  validate :within_daily_upload_limit, on: :create

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

    return if csv_file.byte_size <= MAX_FILE_SIZE

    errors.add(:csv_file, "size must be #{MAX_FILE_SIZE / 1.megabyte} MB or smaller")
  end

  # A PDF is both the wrong extension and the wrong content type, and reporting
  # both reads as "File must be a CSV file File must have a .csv extension". The
  # extension is the stronger statement, so it answers alone and the content type
  # is only consulted once the name has already passed.
  #
  # The wording here is the wording `rejectionFor` uses in the browser, so a file
  # the client refuses and one the model refuses read the same to the user.
  def csv_file_type
    return unless csv_file.attached?

    unless csv_file.filename.extension_without_delimiter.casecmp("csv").zero?
      errors.add(:csv_file, "must be a CSV file")
      return
    end

    content_type = csv_file.content_type.to_s.split(";").first.to_s.strip
    errors.add(:csv_file, "must be a CSV file") if content_type.present? && !CSV_CONTENT_TYPES.include?(content_type)
  end

  # The day's allowance, counted against what this user has already stored plus
  # the file now waiting to be saved. Checking the projection rather than the
  # balance means a file that would cross the line is refused instead of being
  # stored and refused afterwards.
  def within_daily_upload_limit
    return unless csv_file.attached?
    return if created_by.blank?

    projected = self.class.uploaded_bytes_today(created_by) + csv_file.byte_size
    return if projected <= DAILY_UPLOAD_LIMIT

    errors.add(:csv_file, "exceeds your daily upload limit of #{DAILY_UPLOAD_LIMIT / 1.megabyte} MB")
  end
end
