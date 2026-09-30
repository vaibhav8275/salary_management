module Api
  module V1
    class SalaryImportsController < ApplicationController
      # An import over the 10,000-employee dataset can reject most of its rows,
      # so the detail page pages rather than returning every error at once. Fixed
      # rather than client-supplied: there is no reason for a caller to choose a
      # different page size, and an unbounded one would let a single request pull
      # 10,000 rows.
      ERRORS_PER_PAGE = 50

      # Accept the file, record the import,
      # hand the work to the queue.
      #
      # The record and its attachment are saved together, so a file that fails
      # validation leaves nothing behind: no import row stuck at `pending`, and
      # no uploaded object that no import points at. That is the main reason the
      # CSV moved from a hand-rolled S3 service to Active Storage — the previous
      # order had to upload first and create the row second, because the two were
      # unrelated as far as the database was concerned.
      def create
        import = SalaryImport.new(
          filename: filename,
          status: :pending,
          total_records: 0,
          processed_records: 0,
          failed_records: 0,
          created_by: current_user.id
        )
        import.csv_file.attach(csv_upload)

        return render_error(message: import.errors.full_messages.to_sentence) unless import.save

        SalaryImportJob.perform_later(import.id)

        render_data(SalaryImportBlueprint.render_as_hash(import), status: :created)
      end

      def index
        imports = SalaryImport.includes(:uploader).order(id: :desc)
        render_data(SalaryImportBlueprint.render_as_hash(imports))
      end

      def show
        render_data(SalaryImportBlueprint.render_as_hash(SalaryImport.includes(:uploader).find(params[:id])))
      end

      # The rows behind `failed_records`, one page at a time.
      #
      # A summary of the same rows is returned alongside the page rather than as a
      # second endpoint: it is a roll-up of exactly this collection, and asking
      # for it separately would let the two disagree if an import were still
      # running between the requests.
      def errors
        import = SalaryImport.find(params[:id])
        errors = import.salary_import_errors.order(:row_number, :id)

        page = params[:page].to_i
        page = 1 if page < 1
        per_page = ERRORS_PER_PAGE

        total_count = errors.count
        rows = errors.limit(per_page).offset((page - 1) * per_page)

        render json: {
          data: SalaryImportErrorBlueprint.render_as_hash(rows),
          meta: {
            "current_page" => page,
            "per_page" => per_page,
            "total_count" => total_count,
            "total_pages" => (total_count.to_f / per_page).ceil
          },
          summary: error_summary(import)
        }
      end

      # The uploaded CSV, sent back under the name it was uploaded with.
      #
      # Deliberately not a signed storage URL: those put a token in a URL the
      # browser can read and send the user to a different origin, which breaks
      # the rule that the browser only ever talks to this API. The same rule
      # keeps the storage key out of the response — only the human filename is
      # ever named, and it came from `File.basename` at upload.
      #
      # A blob can be gone while the attachment record remains (that is exactly
      # the state the job's `rescue` handles), so a missing file is a 404 rather
      # than a 500.
      def csv
        import = SalaryImport.find(params[:id])
        attachment = import.csv_file

        unless attachment.attached?
          return render_error(status: :not_found, code: "file_missing", message: "the uploaded file is no longer available")
        end

        send_data attachment.download, filename: sanitized_filename(import), type: "text/csv", disposition: "attachment"
      rescue ActiveStorage::FileNotFoundError
        render_error(status: :not_found, code: "file_missing", message: "the uploaded file is no longer available")
      end

      private

      # Header values cannot carry newlines or quotes, and the filename comes from
      # an uploaded file. `File.basename` already dropped any directory part at
      # upload; this closes off the remaining header-injection route. A name that
      # sanitises away to nothing falls back to a constant rather than sending an
      # empty filename.
      def sanitized_filename(import)
        name = import.filename.to_s.delete("[\r\n\"]")
        name.presence || "salary-import.csv"
      end

      # Failure counts per reason, most frequent first.
      #
      # The file-level synthetic row shares this grouping rather than being
      # separated out, so the totals here always reconcile with `total_count`.
      def error_summary(import)
        import.salary_import_errors
              .group(:error_message)
              .order("count_all DESC, error_message ASC")
              .count
              .map { |message, count| { error_message: message, count: count } }
      end

      # Active Storage sanitises the name it stores; `filename` is a separate
      # column because the API reports it back and the original name is what the
      # HR Manager recognises.
      def filename
        upload = csv_upload
        return File.basename(upload.original_filename.to_s) if upload

        ""
      end

      # Nil for a request with no file at all, which `validates :csv_file,
      # presence: true` turns into the same 422 as a file of the wrong type.
      def csv_upload
        return @csv_upload if defined?(@csv_upload)

        file = params[:file]
        @csv_upload = file if file.respond_to?(:original_filename)
      end
    end
  end
end
