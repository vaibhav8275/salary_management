class SalaryImportBlueprint < Blueprinter::Base
  identifier :id

  fields :filename, :status, :total_records, :processed_records, :failed_records

  # The uploader's email rather than the raw `created_by` id: the number is an
  # internal key with no meaning to a reader, and the list is the only place the
  # person who ran an import is recorded.
  field :created_by do |import|
    import.uploader.email
  end

  field :created_at do |import|
    import.created_at&.iso8601
  end
end
