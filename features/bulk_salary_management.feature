Feature: Bulk salary management
  As the HR Manager I need to upload a CSV of salary changes so that a large
  update does not have to be typed in by hand.

  The upload itself must not do the work (REQUIREMENTS FR-4.6). It creates the
  import record, stores the file in S3, enqueues a job with the import id and
  returns. The worker then applies exactly the same effective-date rules as the
  interactive path (REQUIREMENTS BR-5).

  Background:
    Given an employee "Ada Lovelace" exists with currency "USD"

  # REQUIREMENTS FR-4.1, LLD §8.1
  Scenario: Upload a salary CSV
    Given a salary CSV file "salaries.csv" with:
      | employee     | effective_date | base_salary | bonus | allowance |
      | Ada Lovelace | 2026-01-01     | 60000       | 0     | 0         |
    When the HR Manager uploads the salary CSV "salaries.csv"
    Then the response should be successful
    And the response should contain an import id
    And the import should be recorded with status "pending"
    And the import should record the filename "salaries.csv"
    And the import should record the uploading user
    And the import should reference an uploaded file

  # REQUIREMENTS FR-4.6, LLD §8.1
  Scenario: Uploading does not process the CSV synchronously
    Given a salary CSV file "salaries.csv" with:
      | employee     | effective_date | base_salary | bonus | allowance |
      | Ada Lovelace | 2026-01-01     | 60000       | 0     | 0         |
    When the HR Manager uploads the salary CSV "salaries.csv"
    Then the employee "Ada Lovelace" should have exactly 0 salary records
    And a salary import job should be enqueued for the import

  # LLD §8.1 — the job receives the import id alone, never the file itself
  Scenario: The job is enqueued with the import id only
    Given a salary CSV file "salaries.csv" with:
      | employee     | effective_date | base_salary | bonus | allowance |
      | Ada Lovelace | 2026-01-01     | 60000       | 0     | 0         |
    When the HR Manager uploads the salary CSV "salaries.csv"
    Then the job should be enqueued with only the import id

  # LLD §13 — file type validation on upload
  Scenario: Uploading a file that is not a CSV is rejected
    Given a non-CSV file "salaries.xlsx" with content "not a csv"
    When the HR Manager uploads the salary CSV "salaries.xlsx"
    Then the response status should be 422
    And no salary import should have been created

  # REQUIREMENTS FR-4.2, LLD §5.2
  Scenario: A newer effective date creates a new salary record
    Given the employee "Ada Lovelace" has a salary of 60000 USD effective from 2026-01-01
    And a salary CSV file "salaries.csv" with:
      | employee     | effective_date | base_salary | bonus | allowance |
      | Ada Lovelace | 2027-01-01     | 65000       | 0     | 0         |
    When the HR Manager uploads the salary CSV "salaries.csv"
    And the HR Manager processes the import
    Then the import should be recorded with status "completed"
    And the employee "Ada Lovelace" should have exactly 2 salary records
    And the salary for 2026-01-01 for "Ada Lovelace" should be 60000 USD
    And the salary for 2027-01-01 for "Ada Lovelace" should be 65000 USD

  # REQUIREMENTS FR-4.2, LLD §7.2 — import provenance lives on the version
  Scenario: An import created record is attributed to the import
    Given a salary CSV file "salaries.csv" with:
      | employee     | effective_date | base_salary | bonus | allowance |
      | Ada Lovelace | 2026-01-01     | 60000       | 0     | 0         |
    When the HR Manager uploads the salary CSV "salaries.csv"
    And the HR Manager processes the import
    And the HR Manager views the audit history of "Ada Lovelace"
    Then the audit history should report source "bulk_import"
    And the audit history should report the import id
    And the audit history should report the actor "HR Manager"

  # REQUIREMENTS FR-4.3, LLD §5.3
  Scenario: A changed value for the same period updates the existing record
    Given the employee "Ada Lovelace" has a salary of 60000 USD effective from 2026-01-01
    And a salary CSV file "salaries.csv" with:
      | employee     | effective_date | base_salary | bonus | allowance |
      | Ada Lovelace | 2026-01-01     | 62000       | 0     | 0         |
    When the HR Manager uploads the salary CSV "salaries.csv"
    And the HR Manager processes the import
    Then the import should be recorded with status "completed"
    And the employee "Ada Lovelace" should have exactly 1 salary record
    And the salary for 2026-01-01 for "Ada Lovelace" should be 62000 USD
    And the audit history for "Ada Lovelace" contains 2 entries

  # REQUIREMENTS BR-4, LLD §5.3 — re-importing identical data adds no versions
  Scenario: An identical row is a no-op
    Given the employee "Ada Lovelace" has a salary of 60000 USD effective from 2026-01-01
    And a salary CSV file "salaries.csv" with:
      | employee     | effective_date | base_salary | bonus | allowance |
      | Ada Lovelace | 2026-01-01     | 60000       | 0     | 0         |
    When the HR Manager uploads the salary CSV "salaries.csv"
    And the HR Manager processes the import
    Then the import should be recorded with status "completed"
    And the employee "Ada Lovelace" should have exactly 1 salary record
    And the audit history for "Ada Lovelace" contains 1 entry

  # REQUIREMENTS BR-7, LLD §5.4
  Scenario: An older effective date is skipped as stale
    Given the employee "Ada Lovelace" has a salary of 60000 USD effective from 2026-01-01
    And a salary CSV file "salaries.csv" with:
      | employee     | effective_date | base_salary | bonus | allowance |
      | Ada Lovelace | 2025-01-01     | 55000       | 0     | 0         |
    When the HR Manager uploads the salary CSV "salaries.csv"
    And the HR Manager processes the import
    Then the import should be recorded with status "completed"
    And the employee "Ada Lovelace" should have exactly 1 salary record
    And the salary for 2026-01-01 for "Ada Lovelace" should be 60000 USD
    And row 2 should be reported as skipped

  # REQUIREMENTS FR-6.4 — "failed/skipped" are counted together, so a stale row
  # increments failed_records. LLD §2.6 does not state this explicitly; it is an
  # open question flagged for confirmation.
  Scenario: A stale row is counted as a failed row
    Given the employee "Ada Lovelace" has a salary of 60000 USD effective from 2026-01-01
    And a salary CSV file "salaries.csv" with:
      | employee     | effective_date | base_salary | bonus | allowance |
      | Ada Lovelace | 2025-01-01     | 55000       | 0     | 0         |
    When the HR Manager uploads the salary CSV "salaries.csv"
    And the HR Manager processes the import
    Then the import should record 1 total, 0 processed and 1 failed rows

  # REQUIREMENTS BR-7 — the worked example from REQUIREMENTS §3.5
  Scenario: A stale export does not overwrite newer salary data
    Given the employee "Ada Lovelace" has a salary of 60000 USD effective from 2026-01-01
    And a salary CSV file "old-export.csv" with:
      | employee     | effective_date | base_salary | bonus | allowance |
      | Ada Lovelace | 2025-01-01     | 55000       | 0     | 0         |
    When the HR Manager uploads the salary CSV "old-export.csv"
    And the HR Manager processes the import
    Then the employee "Ada Lovelace" should have exactly 1 salary record
    And the salary for 2026-01-01 for "Ada Lovelace" should be 60000 USD
    And the salary for 2025-01-01 for "Ada Lovelace" should not exist
    And row 2 should be reported as skipped

  # REQUIREMENTS FR-4.4, FR-4.5
  Scenario: A row for an unknown employee is reported as an error
    Given a salary CSV file "salaries.csv" with:
      | employee     | effective_date | base_salary | bonus | allowance |
      | Nobody Here  | 2026-01-01     | 60000       | 0     | 0         |
    When the HR Manager uploads the salary CSV "salaries.csv"
    And the HR Manager processes the import
    Then the import should be recorded with status "completed_with_errors"
    And the import should have 1 failed row
    And row 2 should be reported as failed with a message mentioning "employee"

  # REQUIREMENTS FR-4.4
  Scenario: A row with a malformed effective date is reported as an error
    Given a salary CSV file "salaries.csv" with:
      | employee     | effective_date | base_salary | bonus | allowance |
      | Ada Lovelace | not-a-date     | 60000       | 0     | 0         |
    When the HR Manager uploads the salary CSV "salaries.csv"
    And the HR Manager processes the import
    Then the import should be recorded with status "completed_with_errors"
    And the import should have 1 failed row
    And row 2 should be reported as failed with a message mentioning "date"

  # REQUIREMENTS FR-4.4, LLD §3
  Scenario: A row with a negative base salary is reported as an error
    Given a salary CSV file "salaries.csv" with:
      | employee     | effective_date | base_salary | bonus | allowance |
      | Ada Lovelace | 2026-01-01     | -500        | 0     | 0         |
    When the HR Manager uploads the salary CSV "salaries.csv"
    And the HR Manager processes the import
    Then the import should be recorded with status "completed_with_errors"
    And the import should have 1 failed row

  # REQUIREMENTS FR-4.4
  Scenario: A row with a non numeric base salary is reported as an error
    Given a salary CSV file "salaries.csv" with:
      | employee     | effective_date | base_salary | bonus | allowance |
      | Ada Lovelace | 2026-01-01     | sixty thousand | 0  | 0         |
    When the HR Manager uploads the salary CSV "salaries.csv"
    And the HR Manager processes the import
    Then the import should be recorded with status "completed_with_errors"
    And the import should have 1 failed row

  # REQUIREMENTS FR-6.6, LLD §8.5 — per-row failures, valid rows still applied
  Scenario: A failing row does not stop the valid rows
    Given the employee "Ada Lovelace" has a salary of 50000 USD effective from 2024-01-01
    And a salary CSV file "salaries.csv" with:
      | employee     | effective_date | base_salary | bonus | allowance |
      | Ada Lovelace | 2026-01-01     | 60000       | 0     | 0         |
      | Nobody Here  | 2026-01-01     | 45000       | 0     | 0         |
    When the HR Manager uploads the salary CSV "salaries.csv"
    And the HR Manager processes the import
    Then the import should be recorded with status "completed_with_errors"
    And the employee "Ada Lovelace" should have exactly 2 salary records
    And the salary for 2026-01-01 for "Ada Lovelace" should be 60000 USD
    And the import should have 1 failed row

  # REQUIREMENTS FR-4.5, LLD §2.7 — a rejected row keeps the original data
  Scenario: A rejected row records the original row data
    Given a salary CSV file "salaries.csv" with:
      | employee     | effective_date | base_salary | bonus | allowance |
      | Ada Lovelace | not-a-date     | 60000       | 0     | 0         |
    When the HR Manager uploads the salary CSV "salaries.csv"
    And the HR Manager processes the import
    Then the rejected row should record the original row data

  # REQUIREMENTS FR-6.4
  Scenario: The import records total, processed and failed counts
    Given a salary CSV file "salaries.csv" with:
      | employee     | effective_date | base_salary | bonus | allowance |
      | Ada Lovelace | 2026-01-01     | 60000       | 0     | 0         |
      | Ada Lovelace | 2027-01-01     | 65000       | 0     | 0         |
      | Nobody Here  | 2027-01-01     | 45000       | 0     | 0         |
    When the HR Manager uploads the salary CSV "salaries.csv"
    And the HR Manager processes the import
    Then the import should record 3 total, 2 processed and 1 failed rows

  # REQUIREMENTS FR-6.3, LLD §8.2
  Scenario: The import status lifecycle is persisted
    Given a salary CSV file "salaries.csv" with:
      | employee     | effective_date | base_salary | bonus | allowance |
      | Ada Lovelace | 2026-01-01     | 60000       | 0     | 0         |
    When the HR Manager uploads the salary CSV "salaries.csv"
    And the import should be recorded with status "pending"
    When the HR Manager processes the import
    Then the import should be recorded with status "completed"
    And the import should have a start timestamp

  # REQUIREMENTS FR-6.5
  Scenario: The import records when processing started and finished
    Given a salary CSV file "salaries.csv" with:
      | employee     | effective_date | base_salary | bonus | allowance |
      | Ada Lovelace | 2026-01-01     | 60000       | 0     | 0         |
    When the HR Manager uploads the salary CSV "salaries.csv"
    And the HR Manager processes the import
    Then the import should have a start timestamp
    And the import should have a completion timestamp

  # REQUIREMENTS FR-6.1, LLD §9.3
  Scenario: List past imports
    Given a completed import for "salaries.csv"
    And a pending import for "other.csv"
    When the HR Manager lists salary imports
    Then the response should be successful
    And the import list should contain 2 imports
    And the import list should include an import with status "pending"

  # REQUIREMENTS FR-6.1, LLD §9.3
  Scenario: View the status of one import
    Given a completed import for "salaries.csv"
    When the HR Manager opens the most recent import
    Then the response should be successful
    And the import should be recorded with status "completed"
    And the import should record the filename "salaries.csv"

  # REQUIREMENTS FR-4.7, BR-6 — 2,000 records per batch, provisional
  @scale
  Scenario: A large import is processed in full
    Given a salary CSV file "large.csv" with 2500 salary rows for "Ada Lovelace"
    When the HR Manager uploads the salary CSV "large.csv"
    And the HR Manager processes the import
    Then the import should be recorded with status "completed"
    And the import should record 2500 total, 2500 processed and 0 failed rows
    And the employee "Ada Lovelace" should have exactly 2500 salary records
