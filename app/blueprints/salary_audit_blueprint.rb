class SalaryAuditBlueprint < Blueprinter::Base
  identifier :id

  field :whodunnit
  field :event
  field :source
  field :salary_import_id

  field :created_at do |version|
    version.created_at&.iso8601
  end

  field :changed_by do |version|
    version.whodunnit
  end

  field :changed_at do |version|
    version.created_at&.iso8601
  end

  field :salary_record_id do |version|
    version.item_id
  end

  field :changes do |version|
    audit_changes(version)
  end

  field :changeset do |version|
    audit_changes(version)
  end

  def self.audit_changes(version)
    changeset = version.changeset
    return changeset if version.event == "update" || version.event == "destroy"

    changeset.select { |_key, pair| Array(pair).first.present? }
  end
end
