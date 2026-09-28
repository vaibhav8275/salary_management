Feature: Salary management
  As the HR Manager I need to view and change compensation for an employee so
  that the salary I see is the salary that applies today.

  A salary record is the complete compensation state effective from a date, in
  the currency of the employee's country (LLD §2.5). There is no currency column
  on the record: the country is the only source of truth (BR-8, LLD §2.7).

  Background:
    Given an employee "Ada Lovelace" exists with currency "USD"

  # REQUIREMENTS FR-2.1
  Scenario: View the current salary
    Given the employee "Ada Lovelace" has a salary of 50000 USD effective from 2025-01-01
    When the HR Manager views the current salary of "Ada Lovelace"
    Then the response should be successful
    And the current salary should be 50000 USD effective from 2025-01-01

  # LLD §5.1 — a future-dated record must not become current prematurely
  Scenario: A future dated salary is not the current salary
    Given the employee "Ada Lovelace" has a salary of 50000 USD effective from 2025-01-01
    And the employee "Ada Lovelace" has a future dated salary of 65000 USD effective from 2099-01-01
    When the HR Manager views the current salary of "Ada Lovelace"
    Then the current salary should be 50000 USD effective from 2025-01-01

  # REQUIREMENTS FR-2.1
  Scenario: An employee with no salary yet
    When the HR Manager views the current salary of "Ada Lovelace"
    Then the response should be successful
    And there should be no current salary for "Ada Lovelace"

  # REQUIREMENTS FR-2.3, LLD §5.2 — a new effective date creates a new period
  Scenario: Create a salary record for a new effective period
    Given the employee "Ada Lovelace" has a salary of 60000 USD effective from 2026-01-01
    When the HR Manager creates a salary for "Ada Lovelace" with:
      | base_salary | bonus | allowance | effective_date |
      | 65000       | 1000  | 500       | 2027-01-01     |
    Then the response should be successful
    And the employee "Ada Lovelace" should have exactly 2 salary records
    And the salary for 2026-01-01 for "Ada Lovelace" should be 60000 USD
    And the salary for 2027-01-01 for "Ada Lovelace" should be 65000 USD

  # REQUIREMENTS FR-2.4, BR-1 — a correction updates the same period
  Scenario: Correct an existing salary record
    Given the employee "Ada Lovelace" has a salary of 60000 USD effective from 2026-01-01
    When the HR Manager updates the salary effective from 2026-01-01 for "Ada Lovelace" with:
      | base_salary | bonus | allowance |
      | 62000       | 250   | 100       |
    Then the response should be successful
    And the employee "Ada Lovelace" should have exactly 1 salary record
    And the salary for 2026-01-01 for "Ada Lovelace" should be 62000 USD

  # LLD §5.3 — identical values are a no-op, and a no-op writes no audit version
  Scenario: Re-applying identical salary values changes nothing
    Given the employee "Ada Lovelace" has a salary of 60000 USD effective from 2026-01-01
    And the audit history for "Ada Lovelace" contains 1 entry
    When the HR Manager updates the salary effective from 2026-01-01 for "Ada Lovelace" with:
      | base_salary | bonus | allowance |
      | 60000       | 0     | 0         |
    Then the response should be successful
    And the salary for 2026-01-01 for "Ada Lovelace" should be 60000 USD
    And the audit history for "Ada Lovelace" contains 1 entry

  # REQUIREMENTS FR-2.7, LLD §3
  Scenario: A negative base salary is rejected
    Given the employee "Ada Lovelace" has a salary of 60000 USD effective from 2026-01-01
    When the HR Manager creates a salary for "Ada Lovelace" with:
      | base_salary | bonus | allowance | effective_date |
      | -100        | 0     | 0         | 2027-01-01     |
    Then the response status should be 422
    And the response should include errors
    And the employee "Ada Lovelace" should have exactly 1 salary record

  # REQUIREMENTS FR-2.7, LLD §3
  Scenario: A negative bonus is rejected
    Given the employee "Ada Lovelace" has a salary of 60000 USD effective from 2026-01-01
    When the HR Manager creates a salary for "Ada Lovelace" with:
      | base_salary | bonus | allowance | effective_date |
      | 60000       | -500  | 0         | 2027-01-01     |
    Then the response status should be 422
    And the employee "Ada Lovelace" should have exactly 1 salary record

  # REQUIREMENTS FR-2.7
  Scenario: A salary without an effective date is rejected
    Given the employee "Ada Lovelace" has a salary of 60000 USD effective from 2026-01-01
    When the HR Manager creates a salary for "Ada Lovelace" with:
      | base_salary | bonus | allowance |
      | 60000       | 0     | 0         |
    Then the response status should be 422
    And the response should include errors
    And the employee "Ada Lovelace" should have exactly 1 salary record

  # REQUIREMENTS FR-2.7
  Scenario: A non numeric base salary is rejected
    Given the employee "Ada Lovelace" has a salary of 60000 USD effective from 2026-01-01
    When the HR Manager creates a salary for "Ada Lovelace" with:
      | base_salary | bonus | allowance | effective_date |
      | not-a-number| 0     | 0         | 2027-01-01     |
    Then the response status should be 422
    And the employee "Ada Lovelace" should have exactly 1 salary record

  # LLD §3 — one record per employee per effective period
  Scenario: A second record for the same effective period is rejected
    Given the employee "Ada Lovelace" has a salary of 60000 USD effective from 2026-01-01
    When the HR Manager creates a salary for "Ada Lovelace" with:
      | base_salary | bonus | allowance | effective_date |
      | 70000       | 0     | 0         | 2026-01-01     |
    Then the response status should be 422
    And the employee "Ada Lovelace" should have exactly 1 salary record
    And the salary for 2026-01-01 for "Ada Lovelace" should be 60000 USD

  # LLD §3 — updating a period that does not exist is not possible
  Scenario: Correcting an effective period that has no record is rejected
    Given the employee "Ada Lovelace" has a salary of 60000 USD effective from 2026-01-01
    When the HR Manager updates the salary effective from 2025-01-01 for "Ada Lovelace" with:
      | base_salary | bonus | allowance |
      | 55000       | 0     | 0         |
    Then the response status should be 404
    And the employee "Ada Lovelace" should have exactly 1 salary record

  # REQUIREMENTS BR-8, LLD §2.5 — amounts are in the employee's currency
  Scenario: Salary amounts are denominated in the employee's own currency
    Given an employee "Marie Curie" exists with currency "EUR"
    And the employee "Marie Curie" has a salary of 55000 effective from 2026-01-01
    When the HR Manager views the current salary of "Marie Curie"
    Then the response should be successful
    And the current salary should be 55000 EUR effective from 2026-01-01

  # LLD §2.5 — the employee's currency is inherited by the whole history
  Scenario: Every historical period uses the employee's currency
    Given an employee "Marie Curie" exists with currency "EUR"
    And the employee "Marie Curie" has a salary of 50000 effective from 2024-01-01
    And the employee "Marie Curie" has a salary of 55000 effective from 2026-01-01
    When the HR Manager views the salary history of "Marie Curie"
    Then the response should be successful
    And the salary for 2024-01-01 for "Marie Curie" should be 50000 EUR
    And the salary for 2026-01-01 for "Marie Curie" should be 55000 EUR
