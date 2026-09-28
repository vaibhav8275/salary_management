Feature: Salary reporting
  As the HR Manager I need to understand compensation across the company so that
  I can see how salary is distributed and how much each country costs.

  Every salary and every report states its currency. Amounts in different
  currencies are never combined into one monetary figure without an explicit
  conversion strategy, which is not in scope (REQUIREMENTS BR-8, LLD §11).

  Background:
    Given the following employees exist:
      | first_name | last_name | email             | department | country        | hire_date  | currency |
      | Ada        | Lovelace  | ada@example.com   | Engineering | United States  | 2019-03-01 | USD      |
      | Grace      | Hopper    | grace@example.com | Engineering | United States  | 2021-07-15 | USD      |
      | Alan       | Turing    | alan@example.com  | Sales       | United Kingdom | 2018-01-01 | GBP      |
      | Kemi       | Adeyemi   | kemi@example.com  | Sales       | Nigeria        | 2020-06-01 | GBP      |
      | Marie      | Curie     | marie@example.com | Research    | France         | 2017-05-01 | EUR      |
    And the following current salaries exist:
      | employee     | base_salary | bonus | allowance | effective_date |
      | Ada Lovelace | 60000       | 0     | 0         | 2026-01-01     |
      | Grace Hopper | 65000       | 0     | 0         | 2026-01-01     |
      | Alan Turing  | 50000       | 0     | 0         | 2026-01-01     |
      | Kemi Adeyemi | 40000       | 0     | 0         | 2026-01-01     |
      | Marie Curie  | 70000       | 0     | 0         | 2026-01-01     |

  # REQUIREMENTS FR-7.1
  Scenario: Average salary by department
    When the HR Manager requests the average salary by department
    Then the response should be successful
    And the average salary for department "Engineering" should be 62500 USD
    And the average salary for department "Sales" should be 45000 GBP
    And the average salary for department "Research" should be 70000 EUR

  # REQUIREMENTS FR-7.1 — department filter
  Scenario: Average salary by department filtered to one department
    When the HR Manager requests the average salary by department for department "Engineering"
    Then the response should be successful
    And the average salary for department "Engineering" should be 62500 USD
    And the report should contain 1 entry

  # REQUIREMENTS FR-7.1 — country filter
  Scenario: Average salary by department filtered to one country
    When the HR Manager requests the average salary by department for country "United States"
    Then the response should be successful
    And the average salary for department "Engineering" should be 62500 USD
    And the report should contain 1 entry

  # REQUIREMENTS FR-7.1 — date range filter
  Scenario: Average salary by department restricted to a date range
    Given the employee "Ada Lovelace" has a salary of 50000 USD effective from 2025-01-01
    And the employee "Grace Hopper" has a salary of 55000 USD effective from 2025-01-01
    When the HR Manager requests the average salary by department between 2025-01-01 and 2025-12-31
    Then the response should be successful
    And the average salary for department "Engineering" should be 52500 USD

  # REQUIREMENTS BR-8, LLD §11 — a department spanning two currencies is split
  Scenario: A department spanning two currencies is reported per currency
    Given "Kemi Adeyemi" is paid in "USD"
    When the HR Manager requests the average salary by department for department "Sales"
    Then the average salary for department "Sales" in "USD" should be 40000
    And the average salary for department "Sales" in "GBP" should be 50000
    And every reported monetary figure should state a currency

  # REQUIREMENTS BR-8
  Scenario: No report mixes currencies into a single figure
    When the HR Manager requests the total payroll by country
    Then every reported monetary figure should state a currency
    And the total payroll for country "United States" should be 125000 USD
    And the total payroll for country "United Kingdom" should be 50000 GBP
    And the total payroll for country "Nigeria" should be 40000 GBP
    And the total payroll for country "France" should be 70000 EUR

  # REQUIREMENTS FR-7.3
  Scenario: Total payroll by country
    When the HR Manager requests the total payroll by country
    Then the response should be successful
    And the total payroll for country "United States" should be 125000 USD
    And the total payroll for country "France" should be 70000 EUR

  # REQUIREMENTS FR-7.2
  Scenario: Salary distribution
    When the HR Manager requests the salary distribution
    Then the response should be successful
    And the salary distribution should account for 5 employees in total
    And every reported monetary figure should state a currency

  # REQUIREMENTS FR-7.2 — the distribution follows the same filters
  Scenario: Salary distribution for one department
    When the HR Manager requests the salary distribution for department "Research"
    Then the response should be successful
    And the salary distribution should account for 1 employee in total

  # REQUIREMENTS FR-7.4
  Scenario: Salary trends over time
    Given the employee "Ada Lovelace" has a salary of 50000 USD effective from 2025-01-01
    And the employee "Grace Hopper" has a salary of 55000 USD effective from 2025-01-01
    And the employee "Marie Curie" has a salary of 65000 EUR effective from 2025-01-01
    When the HR Manager requests the salary trends for department "Engineering"
    Then the response should be successful
    And the salary trend should report an average of 52500 effective from 2025-01-01
    And the salary trend should report an average of 62500 effective from 2026-01-01
    And the report should contain 2 entries

  # REQUIREMENTS FR-7.4 — a date range bounds the trend series
  Scenario: Salary trends restricted to a date range
    Given the employee "Ada Lovelace" has a salary of 50000 USD effective from 2025-01-01
    And the employee "Grace Hopper" has a salary of 55000 USD effective from 2025-01-01
    When the HR Manager requests the salary trends for department "Engineering" between 2025-01-01 and 2025-12-31
    Then the response should be successful
    And the salary trend should report an average of 52500 effective from 2025-01-01
    And the salary trend should report no average of 62500 effective from 2026-01-01
    And the report should contain 1 entry

  # REQUIREMENTS FR-7.5
  Scenario: Employee counts by department
    When the HR Manager requests employee counts by department
    Then the response should be successful
    And the employee count for department "Engineering" should be 2
    And the employee count for department "Sales" should be 2
    And the employee count for department "Research" should be 1

  # REQUIREMENTS FR-7.5
  Scenario: Employee counts by country
    When the HR Manager requests employee counts by country
    Then the response should be successful
    And the employee count for country "United States" should be 2
    And the employee count for country "United Kingdom" should be 1
    And the employee count for country "Nigeria" should be 1
    And the employee count for country "France" should be 1

  # REQUIREMENTS FR-7.5 — department and country filters
  Scenario: Employee counts filtered by department
    When the HR Manager requests employee counts by department for department "Sales"
    Then the response should be successful
    And the employee count for department "Sales" should be 2
    And the report should contain 1 entry

  # Reports should degrade to an empty result, not an error, when nothing matches
  Scenario: A report with no matching data returns an empty result
    When the HR Manager requests the average salary by department for country "Atlantis"
    Then the response should be successful
    And the report should be empty

  Scenario: A report over an employee with no salaries is empty
    Given an employee "No Salary" exists with department "Contractors" and country "Atlantis"
    When the HR Manager requests the average salary by department for department "Contractors"
    Then the response should be successful
    And the report should be empty
