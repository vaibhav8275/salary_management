Feature: Salary history and audit history
  As the HR Manager I need to see what a salary was over time, and separately
  see who changed what and when.

  Salary history and audit history answer different questions and must not be
  conflated (REQUIREMENTS BR-3):

    salary history — what salary was effective, and from when
    audit history  — what changed, when, by whom, and from which source

  Background:
    Given an employee "Ada Lovelace" exists with currency "USD"

  # REQUIREMENTS FR-2.2, FR-2.7
  Scenario: View all historical salary records
    Given the employee "Ada Lovelace" has salary history:
      | effective_date | base_salary | bonus | allowance |
      | 2025-01-01     | 50000       | 0     | 0         |
      | 2026-01-01     | 60000       | 500   | 300       |
      | 2027-01-01     | 65000       | 0     | 0         |
    When the HR Manager views the salary history of "Ada Lovelace"
    Then the response should be successful
    And the salary history should contain 3 records
    And the salary history should be ordered by effective date descending
    And the salary for 2027-01-01 for "Ada Lovelace" should be 65000 USD
    And the salary for 2026-01-01 for "Ada Lovelace" should be 60000 USD
    And the salary for 2025-01-01 for "Ada Lovelace" should be 50000 USD

  # REQUIREMENTS FR-2.2
  Scenario: An employee with no salary history
    When the HR Manager views the salary history of "Ada Lovelace"
    Then the response should be successful
    And the salary history should contain 0 records

  # REQUIREMENTS BR-2
  Scenario: The current salary is the latest record that is not in the future
    Given the employee "Ada Lovelace" has salary history:
      | effective_date | base_salary | bonus | allowance |
      | 2025-01-01     | 50000       | 0     | 0         |
      | 2026-01-01     | 60000       | 0     | 0         |
    And the employee "Ada Lovelace" has a future dated salary of 90000 USD effective from 2099-01-01
    When the HR Manager views the current salary of "Ada Lovelace"
    Then the current salary should be 60000 USD effective from 2026-01-01

  # REQUIREMENTS BR-3
  Scenario: Salary history and audit history are separate views
    Given the employee "Ada Lovelace" has salary history:
      | effective_date | base_salary | bonus | allowance |
      | 2025-01-01     | 50000       | 0     | 0         |
    And the salary for 2025-01-01 for "Ada Lovelace" was updated to 52000 USD by the HR Manager
    When the HR Manager views the salary history of "Ada Lovelace"
    And the HR Manager views the audit history of "Ada Lovelace"
    Then the salary history should contain 1 record
    And the audit history for "Ada Lovelace" contains 2 entries
    And the audit history should report the change from 50000 to 52000

  # REQUIREMENTS FR-2.5, LLD §7.1 — who, when, what, previous, new, source
  Scenario: Audit history answers who changed what and where the change came from
    Given the employee "Ada Lovelace" has salary history:
      | effective_date | base_salary | bonus | allowance |
      | 2025-01-01     | 50000       | 0     | 0         |
    And the salary for 2025-01-01 for "Ada Lovelace" was updated to 52000 USD by the HR Manager
    When the HR Manager views the audit history of "Ada Lovelace"
    Then the response should be successful
    And the audit history for "Ada Lovelace" contains 2 entries
    And the audit history entry should be an "update" event
    And the audit history should report the change from 50000 to 52000
    And the audit history should report the actor "HR Manager"
    And the audit history should report source "manual"
    And the audit history should report a change time

  # REQUIREMENTS BR-4 — no version without a change
  Scenario: Re-applying unchanged values does not grow the audit trail
    Given the employee "Ada Lovelace" has salary history:
      | effective_date | base_salary | bonus | allowance |
      | 2025-01-01     | 50000       | 0     | 0         |
    And the audit history for "Ada Lovelace" contains 1 entry
    When the HR Manager updates the salary effective from 2025-01-01 for "Ada Lovelace" with:
      | base_salary | bonus | allowance |
      | 50000       | 0     | 0         |
    Then the response should be successful
    And the audit history for "Ada Lovelace" contains 1 entry
    And the audit history for "Ada Lovelace" should not contain a change to 50000

  # REQUIREMENTS FR-2.5 — the audit history is reported per salary record, so a
  # record's own log can be read without the changes of its neighbours.
  Scenario: The audit history is grouped by the salary record it belongs to
    Given the employee "Ada Lovelace" has salary history:
      | effective_date | base_salary | bonus | allowance |
      | 2025-01-01     | 50000       | 0     | 0         |
      | 2026-01-01     | 60000       | 0     | 0         |
    And the salary for 2025-01-01 for "Ada Lovelace" was updated to 52000 USD by the HR Manager
    When the HR Manager views the audit history of "Ada Lovelace"
    Then the response should be successful
    And the audit history for "Ada Lovelace" is grouped by salary record
    And the audit history group for 2025-01-01 for "Ada Lovelace" contains 2 entries
    And the audit history group for 2026-01-01 for "Ada Lovelace" contains 1 entry

  # A record that was added but never edited has nothing but its create to
  # report, so its group is a single entry rather than an empty one.
  Scenario: A salary record that was never edited reports only its creation
    Given the employee "Ada Lovelace" has salary history:
      | effective_date | base_salary | bonus | allowance |
      | 2025-01-01     | 50000       | 0     | 0         |
    And the salary for 2025-01-01 for "Ada Lovelace" was updated to 52000 USD by the HR Manager
    When the HR Manager views the audit history of "Ada Lovelace"
    Then the audit history group for 2025-01-01 for "Ada Lovelace" contains 2 entries
    And the audit history should report the change from 50000 to 52000

  # REQUIREMENTS FR-2.7 — history is preserved, never overwritten
  Scenario: A new effective period leaves earlier periods intact
    Given the employee "Ada Lovelace" has salary history:
      | effective_date | base_salary | bonus | allowance |
      | 2025-01-01     | 50000       | 0     | 0         |
      | 2026-01-01     | 60000       | 0     | 0         |
    When the HR Manager creates a salary for "Ada Lovelace" with:
      | base_salary | bonus | allowance | effective_date |
      | 65000       | 0     | 0         | 2027-01-01     |
    Then the response should be successful
    And the employee "Ada Lovelace" should have exactly 3 salary records
    And the salary for 2025-01-01 for "Ada Lovelace" should be 50000 USD
    And the salary for 2026-01-01 for "Ada Lovelace" should be 60000 USD
    And the salary for 2027-01-01 for "Ada Lovelace" should be 65000 USD
