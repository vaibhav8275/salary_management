# Audit-trail helpers (LLD §7, REQUIREMENTS BR-3/BR-4).
#
# PaperTrail's `request` object is thread-local, so every helper that sets an
# actor does so inside a block and lets PaperTrail reset it afterwards. This
# keeps one example from leaking its whodunnit into the next.
module AuditHelpers
  # REQUIREMENTS §2 — there is a single persona in the initial scope.
  HR_MANAGER = "HR Manager".freeze

  SOURCE_MANUAL = "manual".freeze
  SOURCE_BULK_IMPORT = "bulk_import".freeze

  def versions_for(record)
    PaperTrail::Version
      .where(item_type: record.class.name, item_id: record.id)
      .order(:id)
  end

  def version_count_for(record)
    versions_for(record).count
  end

  def latest_version_for(record)
    versions_for(record).last
  end

  # The sequence of values a tracked attribute went through, oldest first. A
  # create version records no changes, so it contributes nothing. Decimals are
  # normalised with BigDecimal#to_s("F") because the JSON round trip can produce
  # either "60000.0" or "0.6e5" depending on the magnitude.
  def version_amounts(record, attribute)
    versions_for(record).filter_map do |version|
      changes = version.object_changes&.dig(attribute)
      next if changes.nil?

      BigDecimal(Array(changes).last.to_s).to_s("F")
    end
  end

  # A change made by the HR Manager through the UI: source "manual", no import.
  def as_hr_manager
    PaperTrail.request(whodunnit: HR_MANAGER) { yield }
  end

  # A change made while processing a bulk import. Provenance is recorded on the
  # version only — SalaryRecord has no salary_import_id column (LLD §7.3).
  def as_bulk_import(salary_import)
    PaperTrail.request(
      whodunnit: HR_MANAGER,
      controller_info: { source: SOURCE_BULK_IMPORT, salary_import_id: salary_import.id }
    ) { yield }
  end
end
