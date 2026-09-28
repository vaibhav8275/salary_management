Feature: Employee directory
  As the HR Manager I need to find the right employee quickly so that I am
  always looking at the correct person's compensation.

  Around 10,000 employees are in scope, so searching, filtering and pagination
  all have to stay usable at that size (REQUIREMENTS §1, FR-1.7).

  # REQUIREMENTS FR-1.1, FR-1.2
  Scenario: Employee details are shown in the directory
    Given the following employees exist:
      | first_name | last_name | email             | department | country       | hire_date  |
      | Ada        | Lovelace  | ada@example.com   | Engineering | United States | 2019-03-01 |
      | Grace      | Hopper    | grace@example.com | Engineering | United States | 2021-07-15 |
    When the HR Manager lists employees
    Then the response should be successful
    And the employee list should contain 2 employees
    And the employee list should include the employee id and name
    And the employee "Ada Lovelace" should have department "Engineering"
    And the employee "Ada Lovelace" should have country "United States"
    And the employee "Ada Lovelace" should have hire date "2019-03-01"
    And the employee "Ada Lovelace" should have email "ada@example.com"

  # REQUIREMENTS FR-1.3
  Scenario: Search employees by employee id
    Given the following employees exist:
      | first_name | last_name | email             | department | country       | hire_date  |
      | Ada        | Lovelace  | ada@example.com   | Engineering | United States | 2019-03-01 |
      | Grace      | Hopper    | grace@example.com | Sales       | United States | 2021-07-15 |
    When the HR Manager searches employees for the employee id of "Grace Hopper"
    Then the response should be successful
    And the employee list should contain 1 employee
    And the employee "Grace Hopper" should be in the employee list
    And the employee "Ada Lovelace" should not be in the employee list

  # REQUIREMENTS FR-1.3
  Scenario Outline: Search employees by name
    Given the following employees exist:
      | first_name | last_name | email             | department | country       | hire_date  |
      | Ada        | Lovelace  | ada@example.com   | Engineering | United States | 2019-03-01 |
      | Grace      | Hopper    | grace@example.com | Sales       | United States | 2021-07-15 |
    When the HR Manager searches employees for "<term>"
    Then the response should be successful
    And the employee list should contain 1 employee
    And the employee "<expected>" should be in the employee list

    Examples:
      | term        | expected       |
      | Ada         | Ada Lovelace   |
      | Lovelace    | Ada Lovelace   |
      | Ada Lovelace| Ada Lovelace   |
      | grace       | Grace Hopper   |
      | Hopper      | Grace Hopper   |

  # REQUIREMENTS FR-1.4
  Scenario: Filter employees by department
    Given the following employees exist:
      | first_name | last_name | email             | department | country       | hire_date  |
      | Ada        | Lovelace  | ada@example.com   | Engineering | United States | 2019-03-01 |
      | Grace      | Hopper    | grace@example.com | Sales       | United States | 2021-07-15 |
      | Alan       | Turing    | alan@example.com  | Engineering | United Kingdom | 2018-01-01 |
    When the HR Manager filters employees by department "Engineering"
    Then the response should be successful
    And the employee list should contain 2 employees
    And the employee "Ada Lovelace" should be in the employee list
    And the employee "Alan Turing" should be in the employee list
    And the employee "Grace Hopper" should not be in the employee list

  # REQUIREMENTS FR-1.4
  Scenario: Filter employees by country
    Given the following employees exist:
      | first_name | last_name | email             | department | country        | hire_date  |
      | Ada        | Lovelace  | ada@example.com   | Engineering | United States  | 2019-03-01 |
      | Grace      | Hopper    | grace@example.com | Sales       | United States  | 2021-07-15 |
      | Alan       | Turing    | alan@example.com  | Engineering | United Kingdom | 2018-01-01 |
    When the HR Manager filters employees by country "United Kingdom"
    Then the response should be successful
    And the employee list should contain 1 employee
    And the employee "Alan Turing" should be in the employee list
    And the employee "Ada Lovelace" should not be in the employee list

  # REQUIREMENTS FR-1.4
  Scenario: Filter employees by department and country together
    Given the following employees exist:
      | first_name | last_name | email             | department | country        | hire_date  |
      | Ada        | Lovelace  | ada@example.com   | Engineering | United States  | 2019-03-01 |
      | Grace      | Hopper    | grace@example.com | Sales       | United States  | 2021-07-15 |
      | Alan       | Turing    | alan@example.com  | Engineering | United Kingdom | 2018-01-01 |
    When the HR Manager filters employees by department "Engineering" and country "United Kingdom"
    Then the response should be successful
    And the employee list should contain 1 employee
    And the employee "Alan Turing" should be in the employee list

  # REQUIREMENTS FR-1.5
  Scenario: Paginate the employee list
    Given 12 employees exist in department "Engineering"
    When the HR Manager lists employees on page 2 with 5 per page
    Then the response should be successful
    And the employee list should contain 5 employees
    And the pagination meta should report page 2
    And the pagination meta should report 5 per page
    And the pagination meta should report 12 total records
    And the pagination meta should report 3 total pages

  # REQUIREMENTS FR-1.5
  Scenario: A page beyond the end of the results is empty rather than an error
    Given 3 employees exist in department "Engineering"
    When the HR Manager lists employees on page 9 with 10 per page
    Then the response should be successful
    And the employee list should contain 0 employees
    And the pagination meta should report 3 total records

  # REQUIREMENTS FR-1.6
  Scenario: Open an employee detail view
    Given an employee "Ada Lovelace" exists with department "Engineering" and country "United States"
    When the HR Manager opens the employee "Ada Lovelace"
    Then the response should be successful
    And the employee detail should show email "ada@example.com"
    And the employee detail should show the currency "USD"

  # REQUIREMENTS FR-1.6
  Scenario: Requesting an unknown employee returns not found
    When the HR Manager opens employee 999999
    Then the response status should be 404
    And the response should include errors

  # REQUIREMENTS FR-1.7 — correctness at the target dataset size. Query plans and
  # response times are validated separately (LLD §4); this guards against
  # filtering or search silently dropping rows once the table is large.
  @scale
  Scenario: Searching a 10,000 employee dataset returns the right employee
    Given 10000 employees exist in department "Bulk Department"
    When the HR Manager searches employees for "Bulk Employee5000"
    Then the response should be successful
    And the employee list should contain 1 employee
    And the employee "Bulk Employee5000" should be in the employee list
