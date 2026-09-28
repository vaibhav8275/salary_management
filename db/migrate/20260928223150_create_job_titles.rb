class CreateJobTitles < ActiveRecord::Migration[8.1]
  def change
    # Reference data an employee belongs to, mirroring `departments` (§2.4).
    # The title is standardized — trimmed, interior spaces squeezed, and
    # unique case-insensitively — so one role cannot exist under several
    # spellings and split a title-based report in two. The uniqueness itself is
    # enforced by the model (§2.9) because PostgreSQL has no case-insensitive
    # unique constraint without an extension; the plain index below serves the
    # name-to-id lookups the directory and CSV import use.
    create_table :job_titles do |t|
      t.string :title, null: false

      t.timestamps
    end

    add_index :job_titles, :title, unique: true
  end
end
