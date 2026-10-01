# Employee Salary Management System — Requirements

> **Scope of this document:** what the system must do and why. Technology
> choices live in [`ARCHITECTURE.md`](ARCHITECTURE.md); tables, services and
> endpoints live in [`LLD.md`](LLD.md).

## 1. Purpose

Provide the HR Manager with web-based software to manage salary information for
approximately 10,000 employees across multiple countries, replacing
spreadsheet-based salary management.

The application allows HR to search employees, view and manage compensation,
review salary history, perform bulk salary updates, and understand compensation
through reporting and queries.

## 2. User Persona

**HR Manager** — the only persona in the initial scope. No employee
self-service, administrator or payroll persona exists yet.

## 3. Functional Scope

### 3.1 Employee directory

| ID       | Requirement                                     |
| -------- | ----------------------------------------------- |
| FR-1.1   | Display employee information                    |
| FR-1.2   | Display employee ID, name, department, job title, country and hire date |
| FR-1.3   | Search by employee ID or name                   |
| FR-1.4   | Filter by department, country and job title     |
| FR-1.5   | Paginate employee results                       |
| FR-1.6   | Provide an employee detail view                 |

The directory must operate efficiently against approximately 10,000 employees
(FR-1.7).

### 3.2 Salary record management

Salary information for an employee consists of base salary, bonus, allowance and
effective date, denominated in the currency of the country the employee belongs
to.

| ID       | Requirement                                              |
| -------- | -------------------------------------------------------- |
| FR-2.1   | View the current salary                                  |
| FR-2.2   | View all historical salary records                       |
| FR-2.3   | Create a salary record for a new effective period        |
| FR-2.4   | Edit an existing salary record                           |
| FR-2.5   | Review changes through per-record audit history          |
| FR-2.6   | Validate salary input                                    |
| FR-2.7   | Preserve salary history when compensation changes        |

**BR-1 — Salary history rule.** A salary change with a **new effective date**
creates a new salary record. An edit to an existing effective period
updates that existing record rather than creating a second record for the same
effective date.

```text
2025-01-01 → $50,000
2026-01-01 → $60,000
2027-01-01 → $65,000
```

**BR-2 — Current salary.** The current salary is the salary record with the
latest effective date that is not in the future, so a future-dated record never
becomes current prematurely. The exact query is specified in
[`LLD.md`](LLD.md).

### 3.3 Audit history

**BR-3 — Two separate histories.** Salary history and audit history are distinct
concepts and must not be conflated.

> **Salary history** answers: *What salary was effective for this employee?*
>
> **Audit history** answers: *What changed to this salary record, when did it
> change, and who changed it?*

It is reported **per salary record**. A change log attached to a record is only
useful if it is that record's log; a single combined feed across an employee's
records cannot answer "what happened to *this* period?", and asking the reader to
work that out from interleaved entries is asking them to do the grouping by eye.

**BR-4 — No versions without change.** A new audit version is recorded only when a
tracked value actually changes. Processing an unchanged salary record must not
create a new audit version. This prevents repeated imports of identical data
from generating unnecessary audit records.

### 3.4 Bulk salary management

The HR Manager can upload a CSV containing salary changes.

| ID       | Requirement                                                |
| -------- | ---------------------------------------------------------- |
| FR-4.1   | Accept a CSV upload of salary changes                       |
| FR-4.2   | Create new salary records for new effective periods          |
| FR-4.3   | Update existing salary records when a period is intentionally edited     |
| FR-4.4   | Validate imported data                                      |
| FR-4.5   | Report invalid and skipped rows                            |
| FR-4.6   | Process imports asynchronously, without blocking the request |
| FR-4.7   | Process records in batches                                  |
| FR-4.8   | Report progress and outcome of an import                    |

**BR-5 — Same rules as the UI.** Bulk processing applies the same salary
effective-date rules as interactive updates; the two paths must not diverge.

**BR-6 — Batch size is provisional.** The initial target is approximately 2,000
records per batch. This is an implementation decision that may be adjusted after
performance testing.

### 3.5 Bulk import safety

**BR-7 — Stale protection.** The system must protect newer salary information
from being accidentally overwritten by an old Excel/CSV file. For each employee,
the incoming effective date is compared with the employee's latest existing
salary effective date.

| Incoming record                                   | Outcome                 |
| ------------------------------------------------- | ----------------------- |
| Newer effective date                              | Create new salary record |
| Same effective date, unchanged values             | No-op                   |
| Same effective date, changed values               | Update existing record  |
| Older effective date than the latest existing one | Reject/skip as stale    |

```text
Existing:
2026-01-01 → $60,000

Imported:
2025-01-01 → $55,000

Result:
SKIPPED — stale effective date
```

### 3.6 Import tracking

| ID       | Requirement                                          |
| -------- | ---------------------------------------------------- |
| FR-6.1   | Represent every bulk operation as an import record    |
| FR-6.2   | Record import ID, filename and uploading user         |
| FR-6.3   | Record upload timestamp and processing status         |
| FR-6.4   | Record total, processed and failed/skipped record counts |
| FR-6.5   | Record start and completion timestamps                |
| FR-6.6   | Report per-row failures rather than failing the whole import |

The import moves through a status lifecycle: `pending` → `processing` →
`completed`, `completed_with_errors`, or `failed`. The persisted representation
is specified in [`LLD.md`](LLD.md).

The original CSV/Excel file does not need to be retained in the initial
implementation.

### 3.7 Reporting and salary queries

| ID       | Report / query                                        | Filters                          |
| -------- | ----------------------------------------------------- | -------------------------------- |
| FR-7.1   | Average salary by department                          | Date range, department, country   |
| FR-7.2   | Salary distribution                                   | Date range, department, country   |
| FR-7.3   | Total payroll by country                             | Date range                       |
| FR-7.4   | Salary trends over time                              | Date range                       |
| FR-7.5   | Employee counts by department, country and job title | Department, country, job title  |

**BR-8 — Currency is always explicit.** Every salary and every report states its
currency. A salary is denominated in the currency of the employee's country, so a
country determines exactly one currency and an employee never has a currency of
their own. External foreign-exchange conversion is not included initially, and
salaries in different currencies must not be combined into a misleading single
monetary value without an explicit conversion strategy.

## 4. Data Requirements

The system must be able to represent the following information. Field-level
definitions, types, constraints and indexes are specified in
[`LLD.md`](LLD.md).

| Entity           | Must represent                                                                     |
| ---------------- | ---------------------------------------------------------------------------------- |
| **Employee**     | Employee number/ID, name, email, the department, job title and country they belong to, hire date, timestamps |
| **Salary record** | The complete compensation state — base salary, bonus, allowance — effective from a given date, denominated in the currency of the employee's country, plus timestamps |
| **Country**      | A country employees can belong to, and the currency salaries in it are paid in     |
| **Department**   | A department employees can belong to                                              |
| **Job title**    | The role an employee holds; one canonical spelling per role                        |
| **Currency**     | ISO 4217 code, currency name and display symbol                                    |
| **Import**       | One bulk operation: filename, a reference to the uploaded file, status, record counts, uploading user, start/completion timestamps |
| **Import error** | A rejected or skipped row: row number, employee, error message and the original row data |
| **Audit version**| Who changed a salary record, when, what changed, previous and new value, the source of the change, and which import caused it |

Relationships:

- An employee has many salary records, so that salary history is preserved
  rather than overwritten.
- A salary record is a salary state effective from a particular date.
- Departments and countries are reference data an employee is placed in, not
  free-text attributes typed per employee, so the directory filters and the
  reports can group by them.
- A job title is reference data the same way: an employee belongs to one role,
  stored as a single canonical title, so a role cannot exist under several
  spellings and split a title-based report.
- A country has one currency, and an employee's salary currency is that
  currency — the employee does not carry a currency of their own. Countries that
  are paid in the same currency share one currency: Germany and France both use
  the euro.
- An import record represents a bulk operation, and owns the uploaded file that
  operation processes.
- Import provenance does not belong on individual salary records: a record may
  be written by several imports over its life, so "which import touched this
  row" is audit information carried on the change history, not a property of the
  row.

## 5. Constraints

**Scale and performance**

- The target dataset is approximately 10,000 employees.
- Employee search, filtering and pagination must remain efficient at that scale.
- Large CSV imports must not block the request that uploaded them.
- Reference data — the valid currencies, countries and departments — is small,
  changes rarely, and is needed on nearly every screen. It must be available
  without being re-read from the database on each request, while PostgreSQL
  remains the authoritative copy.

**Technology**

The implementation must use:

- Backend: Ruby on Rails API, PostgreSQL, RSpec, Cucumber, PaperTrail, Sidekiq,
  RuboCop, Brakeman, `rack-cors`.
- Frontend: Next.js, TypeScript, and a component library.
  - Deployment: containerized application deployed with Kamal to a single EC2
    instance reached over an Elastic IP, using RDS for PostgreSQL and S3 for
    uploaded CSV/Excel files. Images are pushed to ECR. Redis runs as a container
    on the same instance, holding the Sidekiq job queues and the reference data
    cache.
- Structure: a monolith. Microservices and distributed architecture are
  deliberately avoided because the stated requirement and dataset size do not
  justify their complexity.

The reasoning behind these choices is recorded in
[`ARCHITECTURE.md`](ARCHITECTURE.md).

**Quality and security gates**

- Automated tests must pass.
- Static quality and security checks must pass: RuboCop for code quality and
  style, Brakeman for Rails security analysis, plus automated CI checks.

## 6. Assumptions

- A single HR Manager persona operates the system; there is no role hierarchy in
  the initial scope.
- Employee number is the employee's identifier, so searching by ID and searching
  by name are both expected to be fast.
- Compensation is expressed as base salary plus bonus plus allowance, per
  currency, per effective period.
- A country is paid in exactly one currency and departments and countries are
  maintained as small reference tables rather than typed per employee, so
  employees are placed in existing rows. An employee's salary currency follows
  from their country; an employee relocating to a country paid in another
  currency is a deliberate change, not a per-record currency override.
- An edit to history is a legitimate HR activity and must be supported
  without destroying the record of the earlier value.
- Old Excel/CSV exports are a realistic failure mode, so stale-import protection
  is a first-class requirement rather than a nice-to-have.
- Batch size, index set and transaction boundaries are provisional and will be
  revised against measured behaviour.

## 7. Deliberately Out of Scope

Excluded from the initial implementation:

- Payroll processing and payment integration
- Employee self-service portal
- Country-specific minimum salary / statutory rule validation
- Role-based access control with multiple roles (including the deferred
  three-role RBAC model)
- Email notifications
- Salary data export
- External foreign-exchange services
- Microservices / distributed architecture
- Retention of the original Excel/CSV documents
- Advanced CSV transactional / whole-file rollback semantics
- Tamper-evident audit storage

These exclusions let the implementation focus on the core salary-management
problem while keeping the architecture extensible.

### Deferred, not rejected

Authentication and authorization are not specified as assessment requirements and
are therefore excluded from the initial implementation.

For a production deployment exposing real compensation data, authentication and
authorization would be introduced at the API boundary — for example, JWT-based
authentication with policy-based authorization.

### Authentication

Compensation data is sensitive, so the API is closed to unauthenticated callers.
The boundary is deliberately thin: one account type, one login endpoint, and a
bearer token on every request.

| ID | Requirement |
|----|-------------|
| AU-1 | The system must reject every request that does not carry a valid bearer token, except the health check. |
| AU-2 | The system must authenticate a caller with an email address and password held by the backend, and must not store that password in plaintext. |
| AU-3 | The system must return the session token in the response of a successful login only. |
| AU-4 | The system must not offer a public account registration, sign-out, or password-reset endpoint. |
| AU-5 | The system must not treat token possession as permission to see everything: the account model stays free of roles until authorization is specified. |

Deliberately not included: multi-factor authentication, single sign-on, token
refresh or revocation, password reset, and per-record authorization. These need
requirements of their own rather than an assumption baked into the code.

## 8. Success Criteria

1. Find employees in a 10,000-employee dataset
2. View current salary
3. View salary history
4. Update salary with validation
5. Edit historical salary records
6. View the change history of each salary record
7. Import salary changes through CSV
8. Process large imports asynchronously
9. Prevent stale imports from overwriting newer data
10. Report skipped/invalid import rows
11. Generate salary reports and queries
12. Provide a responsive UI
13. Pass automated tests
14. Pass static quality/security checks
16. Deploy successfully to the EC2 instance

## 9. Related Documents

- [`ARCHITECTURE.md`](ARCHITECTURE.md) — technology decisions, component
  boundaries, deployment topology, tradeoffs
- [`LLD.md`](LLD.md) — schema, constraints, indexes, salary rules, services,
  endpoints, test structure
