require "securerandom"

module Api
  module V1
    class SalaryImportsController < ApplicationController
      UPLOADING_USER = 1

      def create
        file = params[:file]
        return render_error(message: "a CSV file is required") unless file.is_a?(ActionDispatch::Http::UploadedFile) || file.respond_to?(:original_filename)
        return render_error(message: "only CSV files may be uploaded") unless csv_file?(file)

        s3_key = "imports/#{SecureRandom.uuid}.csv"
        S3StorageService.new.upload(s3_key, file.read, content_type: "text/csv")

        import = SalaryImport.create!(
          filename: File.basename(file.original_filename.to_s),
          s3_object_key: s3_key,
          status: :pending,
          total_records: 0,
          processed_records: 0,
          failed_records: 0,
          created_by: UPLOADING_USER
        )

        SalaryImportJob.perform_later(import.id)

        render_data(SalaryImportBlueprint.render_as_hash(import), status: :created)
      end

      def index
        imports = SalaryImport.order(id: :desc)
        render_data(SalaryImportBlueprint.render_as_hash(imports))
      end

      def show
        render_data(SalaryImportBlueprint.render_as_hash(SalaryImport.find(params[:id])))
      end

      private

      def csv_file?(file)
        File.extname(file.original_filename.to_s).casecmp(".csv").zero? &&
          file.content_type.to_s.split(";").first.strip == "text/csv"
      end
    end
  end
end
