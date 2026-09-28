class SalaryRecord < ApplicationRecord
  belongs_to :employee

  # LLD §7 — the audit trail records who changed a salary, what changed, and
  # whether the change was manual or came from a bulk import.
  has_paper_trail
end
