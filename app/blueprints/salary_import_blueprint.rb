class SalaryImportBlueprint < Blueprinter::Base
  identifier :id

  fields :filename, :status, :total_records, :processed_records, :failed_records

  field :created_at do |import|
    import.created_at&.iso8601
  end
end
