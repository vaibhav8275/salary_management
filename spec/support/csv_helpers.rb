# CSV text for bulk-import examples (LLD §8.2).
#
# Ruby's csv library is deliberately not used here: it is no longer a default gem
# on Ruby 4, and the test suite must not depend on a gem the application has not
# declared yet. Cells are written verbatim instead, so an example can supply
# deliberately malformed values ("not-a-date", "abc") and assert the import's own
# validation rather than the CSV parser's.
module CsvHelpers
  # LLD §8.2 column order, used when a caller does not name its own headers.
  CSV_HEADERS = %w[employee_id effective_date base_salary bonus allowance].freeze

  # A missing key is written as an empty cell, so a partial row is expressible.
  def csv_from_rows(rows, headers: nil)
    headers ||= rows.first&.keys || CSV_HEADERS
    lines = [ headers.map(&:to_s) ]
    rows.each do |row|
      lines << headers.map { |header| row[header.to_s].to_s }
    end

    lines.map { |line| line.join(",") }.join("\n") + "\n"
  end
end
