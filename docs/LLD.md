# ACME Employee Salary Management — Low-Level Design

> **Scope of this document:** how the system is implemented — schema,
> constraints, rules, services, endpoints and test structure. Product scope lives
> in [`REQUIREMENTS.md`](REQUIREMENTS.md); structural and technology decisions
> live in [`ARCHITECTURE.md`](ARCHITECTURE.md).

Items marked **provisional** are initial implementation decisions to be
revisited against measured behaviour.

## 1. Domain Model

```text
Employee
  │
  ├── has_many :salary_records
  │
  └── belongs_to :currency

SalaryRecord
  │
  ├── belongs_to :employee
  └── has_paper_trail

SalaryImport
  │
  ├── has_many :salary_import_errors
  └── tracks one bulk import operation

Currency
  │
  └── referenced by employees (authoritative source of an employee's currency)
```

An employee has many salary records so that salary history is preserved rather
than overwritten:

```text
Employee E1001

2025-01-01 → $50,000
2026-01-01 → $60,000
2027-01-01 → $65,000
```

### Entity responsibilities

| Entity                | Owns                                                                       |
| --------------------- | -------------------------------------------------------------------------- |
| `Employee`            | Who the person is, how to find them, and the currency their salary is paid in |
| `SalaryRecord`        | The complete compensation state effective from a date, in the employee's currency |
| `Currency`            | Valid currency values and their display                                      |
| `SalaryImport`        | What happened during one bulk operation                                      |
| `SalaryImportError`   | Why an individual row was rejected or skipped                                |
| PaperTrail version    | What changed on a salary record, when, by whom and from which source          |

## 2. Schema

### 2.1 `employees`

```text
id
first_name
last_name
email
department
country
hire_date
currency_id
created_at
updated_at
```

| Field         | Rails type | Null | Notes                              |
| ------------- | ---------- | ---: | ---------------------------------- |
| `id`          | `bigint`   |   No | Rails primary key; **serves as the employee number** |
| `first_name`  | `string`   |   No | Employee first name                |
| `last_name`   | `string`   |   No | Employee last name                 |
| `email`       | `string`   |   No | Employee email; add unique index   |
| `department`  | `string`   |   No | Department name                    |
| `country`     | `string`   |   No | Country name/code                  |
| `currency_id` | `bigint`   |   No | FK → `currencies.id`; **authoritative currency for this employee** |
| `hire_date`   | `date`     |   No | Employee joining date              |
| `created_at`  | `datetime` |   No | Rails timestamp                    |
| `updated_at`  | `datetime` |   No | Rails timestamp                    |

Because `id` is the employee number, employee-number uniqueness is structural —
no separate uniqueness constraint is required.

### 2.2 `currencies`

```text
id
code
name
symbol
created_at
updated_at
```

| Field         | Rails type | Null | Notes                                      |
| ------------- | ---------- | ---: | ------------------------------------------ |
| `id`          | `bigint`   |   No | Rails default primary key                  |
| `code`        | `string(3)`|   No | ISO 4217 code — USD, INR, EUR; unique      |
| `name`        | `string`   |   No | Currency name — US Dollar, Indian Rupee    |
| `symbol`      | `string`   |   No | Display symbol — $, ₹, €                   |
| `created_at`  | `datetime` |   No | Rails timestamp                            |
| `updated_at`  | `datetime` |   No | Rails timestamp                            |

### 2.3 `salary_records`

```text
id
employee_id
base_salary
bonus
allowance
effective_date
created_at
updated_at
```

| Field            | Rails type | Null | Notes                                |
| ---------------- | ---------- | ---: | ------------------------------------ |
| `id`             | `bigint`   |   No | Rails default primary key            |
| `employee_id`    | `bigint`   |   No | FK → `employees.id`                  |
| `base_salary`    | `decimal`  |   No | Monetary amount, non-negative        |
| `bonus`          | `decimal`  |   No | Monetary amount, non-negative        |
| `allowance`      | `decimal`  |   No | Monetary amount, non-negative        |
| `effective_date` | `date`     |   No | Date from which this salary applies  |
| `created_at`     | `datetime` |   No | Rails timestamp                      |
| `updated_at`     | `datetime` |   No | Rails timestamp                      |

A `SalaryRecord` represents the **complete** compensation state effective from
`effective_date` — not an incremental adjustment.

**Currency.** `salary_records` carries no currency column. All amounts on a
salary record are denominated in the currency of the owning employee, reached
via `salary_records.employee_id → employees.currency_id`. The employee's currency
is the single authoritative source; it is not duplicated per record, so it cannot
drift between an employee and their history.

The consequence to keep in mind: an employee's currency applies to their whole
salary history, including past periods. If historical currency ever needs to
differ from the employee's current currency — for example an employee who
relocates — a currency column would have to be added to `salary_records` as a
deliberate, later change rather than introduced implicitly.

### 2.4 `salary_imports`

```text
id
filename
s3_object_key
status
total_records
processed_records
failed_records
created_by
started_at
created_at
updated_at
```

| Field               | Rails type | Null | Notes                                            |
| ------------------- | ---------- | ---: | ------------------------------------------------ |
| `id`                | `bigint`   |   No | Rails default primary key                        |
| `filename`          | `string`   |   No | Original uploaded filename                       |
| `s3_object_key`     | `string`   |   No | Key of the CSV in S3; how the worker locates the file |
| `status`            | `integer`  |   No | Rails enum, see §8.2                             |
| `total_records`     | `integer`  |   No | Total CSV rows                                   |
| `processed_records` | `integer`  |   No | Successfully processed rows, including no-op rows |
| `failed_records`    | `integer`  |   No | Rows that encountered processing errors          |
| `created_by`        | `bigint`   |   No | HR Manager / user identifier                     |
| `started_at`        | `datetime` |  Yes | When background processing starts                |
| `created_at`        | `datetime` |   No | Rails timestamp                                  |
| `updated_at`        | `datetime` |   No | Rails timestamp                                  |

`created_by` references the uploading user. In the initial scope there is no user
table (authentication is out of scope), so this is a plain identifier rather than
a foreign key.

**`SalaryImport` owns the uploaded file.** `s3_object_key` is the single link
between the import operation and its CSV in S3, and it is what lets the API and
the worker stay decoupled: the job is handed only the import id and reads the key
from the database it already has to write to. The object is not retained beyond
processing in the initial implementation.

### 2.5 `salary_import_errors`

```text
id
salary_import_id
row_number
employee_id
error_message
raw_data
created_at
```

| Field              | Rails migration type | Notes                                            |
| ------------------ | -------------------- | ------------------------------------------------ |
| `id`               | `bigint`             | Rails default primary key                        |
| `salary_import_id` | `bigint`             | FK → `salary_imports.id`, indexed                |
| `row_number`       | `integer`            | CSV row number                                   |
| `employee_id`      | `bigint`             | FK → `employees.id`, nullable                    |
| `error_message`    | `text`               | Full error description                           |
| `raw_data`         | `jsonb`              | Original CSV row as structured data              |
| `created_at`       | `datetime`           | Rails timestamp                                  |

Storing the original row makes a rejected import explainable to the HR Manager
without re-uploading the file.

## 3. Data Integrity

Use database constraints where practical; application validations provide the
friendly errors.

```text
employees.currency_id          → FOREIGN KEY → currencies.id
salary_records.employee_id     → FOREIGN KEY → employees.id
salary_records.base_salary     → non-negative, required
salary_records.bonus           → non-negative, required
salary_records.allowance       → non-negative, required
salary_records.effective_date  → required
```

Currency validity is enforced once, on the employee. Because salary records
inherit currency through the employee foreign key, no separate currency
constraint is needed on `salary_records`.

```text
UNIQUE (employee_id, effective_date)
```

This prevents one employee from accidentally holding two salary records for the
same effective period — which is what makes the "one record per period" rule in
§5 enforceable rather than merely conventional.

## 4. Indexes

Initial indexes to consider:

```text
employees.department
employees.country
employees.first_name
employees.last_name
salary_records.employee_id
salary_records.effective_date
```

Composite indexes should be added where query patterns demonstrate their value —
most likely on `salary_records (employee_id, effective_date)`, which serves both
the current-salary lookup and the history view.

The final index set must be validated against actual queries and query plans
rather than added speculatively.

## 5. Salary Rules

These rules are the single implementation of the business rules in
[`REQUIREMENTS.md`](REQUIREMENTS.md). Both the UI path and the bulk import path
go through them.

### 5.1 Current salary

Current salary is the record with the latest effective date that is not in the
future:

```sql
SELECT *
FROM salary_records
WHERE employee_id = ?
  AND effective_date <= CURRENT_DATE
ORDER BY effective_date DESC
LIMIT 1;
```

The `effective_date <= CURRENT_DATE` predicate is what stops a future-dated
record from becoming current prematurely.

### 5.2 Incoming effective date is newer

Creates a **new** `SalaryRecord`, leaving the earlier period intact:

```text
Existing:
2026-01-01 → $60,000

Incoming:
2027-01-01 → $65,000

Result:
2026-01-01 → $60,000
2027-01-01 → $65,000
```

### 5.3 Incoming effective date is the same

A record already exists for that employee and effective date, so the tracked
attributes are compared:

```text
Values identical → NO-OP
                   no update
                   no PaperTrail version

Values differ    → UPDATE existing SalaryRecord
                   PaperTrail creates a version
```

The no-op branch is the reason "no audit version without a change" holds for
imports: re-importing a file whose rows are already applied must not grow the
audit table.

### 5.4 Incoming effective date is older

```text
incoming effective_date < latest existing effective_date
```

The row is **stale** and is skipped:

```text
Existing:
2026-01-01 → $60,000

CSV:
2025-01-01 → $55,000

Result:
SKIPPED
Reason:
Incoming effective date is older than the latest existing salary record.
```

Newer salary information is never overwritten by an older record. This is the
protection against accidentally uploading a stale Excel export.

## 6. Salary Service

Salary changes are centralized in an application/domain service rather than
duplicated between controllers, models and Sidekiq workers:

```text
SalaryService
  ├── create_salary_record
  ├── update_salary_record
  ├── apply_imported_salary
  └── revert_salary_change
```

The service is responsible for:

- Effective-date rules (§5)
- Salary validation
- Detecting no-op updates
- Creating new salary periods
- Updating existing periods
- Rejecting stale imports
- Triggering normal PaperTrail behaviour (including not triggering it on no-ops)

Exact service boundaries may be refined during implementation, but the rules in
§5 must remain in one place.

## 7. Audit Trail (PaperTrail)

`SalaryRecord` is versioned:

```ruby
class SalaryRecord < ApplicationRecord
  has_paper_trail
end
```

PaperTrail is the audit/change history. It is **not** the source of business
salary history.

### 7.1 What a version must answer

```text
Who?
When?
What record?
What changed?
Previous value?
New value?
Source?
```

### 7.2 Source and import metadata

Provenance lives on the **version**, not on the salary record:

```text
For a UI update:
  source         = manual
  salary_import_id = NULL
  whodunnit      = HR Manager

For a bulk import:
  source         = bulk_import
  salary_import_id = 42
  whodunnit      = HR Manager
```

A version created while processing import 42 looks like this:

```text
PaperTrail version
─────────────────────────────
record_type       SalaryRecord
record_id         100
event             update
whodunnit         HR Manager
salary_import_id  42
source            bulk_import
old data / new data
```

This answers both questions the HR system needs to ask:

- *Which salary changes were caused by Import #42?* — query versions where
  `salary_import_id = 42`.
- *Was this change manual or from an import?* — read the version's `source`.

### 7.3 `SalaryRecord` carries no import provenance

`salary_records` deliberately has **no** `salary_import_id` column. The
relationship is recorded only in PaperTrail versions, for a concrete reason:

```text
SalaryRecord #100

is updated by:

Import #10
Import #20
Import #35
```

A single foreign key on the salary record can only hold one of those. It would
either overwrite an earlier relationship, or degenerate into "last modified by
import" — neither of which is part of what the record *is*. `SalaryRecord`
represents salary business history; the fact that some import once wrote to it is
an audit fact, so it belongs in the audit trail where many-to-many history is
natural.

This also keeps import metadata off every salary row that an import happened to
touch, and leaves the business table free of source-specific columns that would
need migrating if a third source (scheduled review, API integration) ever appears.

### 7.4 Configuration to be defined

- Tracked attributes
- Actor / `whodunnit`
- Version metadata: `source` and `salary_import_id` (§7.2)
- Version retention policy
- Revert behaviour (§9)

## 8. Bulk Import Processing

### 8.1 Request flow

```text
HR
 │
 │ Upload CSV
 ▼
Rails API
 │
 ├── Create SalaryImport
 │
 ├── Upload CSV → S3
 │
 └── Enqueue Sidekiq job with salary_import_id
        ↓
     Sidekiq Worker
        ↓
     Fetch CSV from S3
        ↓
     Process each row
```

The API does not synchronously process a large CSV. The job is enqueued with the
import id alone — `SalaryImportJob.perform_async(salary_import.id)` — and the
worker finds the file through `salary_imports.s3_object_key`. Nothing about the
file is passed through the job arguments, so a job can be retried or re-enqueued
without re-uploading anything.

### 8.2 Status

Status is persisted as a Rails enum backed by an integer column:

```ruby
enum :status, {
  pending: 0,
  processing: 1,
  completed: 2,
  completed_with_errors: 3,
  failed: 4
}
```

Lifecycle:

```text
pending
   ↓
processing
   ├──→ completed
   ├──→ completed_with_errors
   └──→ failed
```

The status is a persisted integer rather than an in-memory flag, so an import
survives a worker restart and remains queryable by the UI. Job-level retry and
requeue behaviour on an unrecoverable failure is not specified; it is expected to
be settled during implementation alongside §8.5.

### 8.3 Sidekiq flow

```text
SalaryImportJob.perform_async(salary_import.id)
    ↓
Load SalaryImport, read CSV from s3_object_key
    ↓
Set status = processing
    ↓
Validate row
    ↓
Process batch
    ↓
Apply SalaryService rules
    ↓
Update import counters
    ↓
Complete import
```

**Batch size (provisional):** 2,000 records. This is an initial performance
assumption to be validated through testing, and it is the same figure the
business rules treat as a target.

### 8.4 Row processing

Every row — from any source — follows the same sequence:

```text
Read row
  ↓
Validate employee
  ↓
Validate salary fields
  ↓
Find existing salary record / effective period
  ↓
Determine latest salary effective date
  ↓
Apply effective-date rules
  ↓
Create / update / no-op / skip
  ↓
PaperTrail only if tracked values changed
```

Worked example, starting from an existing `2026-01-01 → $60,000`:

| CSV row                | Action                                             |
| ---------------------- | -------------------------------------------------- |
| `2027-01-01 → $65,000` | `CREATE` — new effective period                     |
| `2026-01-01 → $60,000` | `NO-OP` — identical values, no PaperTrail version   |
| `2026-01-01 → $62,000` | `UPDATE` — same period, changed values, new version |
| `2025-01-01 → $55,000` | `SKIP` — stale effective date                      |

### 8.5 Transaction boundary

CSV processing does not require whole-file atomicity.

Each batch uses an appropriate database transaction boundary so a failure never
leaves an individual database operation partially written. Row-level failures
are reported and recorded rather than rolling back the entire import.

The exact boundary is finalized during implementation and performance testing.

## 9. Revert

The HR Manager can revert a salary change from audit history. The application
restores the previous value through a **normal salary update** rather than
deleting the PaperTrail version:

```text
Initial:            $50,000
Incorrect update:   $60,000
Revert:             $50,000
```

The audit sequence records all three states, and the revert itself creates a new
PaperTrail version. The audit trail is preserved, not rewritten.

## 10. API Surface

Conceptual endpoints; exact naming and response contracts are finalized during
implementation.

### 10.1 Employees and salary

```text
GET   /api/employees
GET   /api/employees/:id
GET   /api/employees/:id/salary
GET   /api/employees/:id/salary/history
PATCH /api/employees/:id/salary/:salary_record_id
```

### 10.2 Audit

```text
GET  /api/employees/:id/salary/audit
POST /api/salary-records/:id/revert
```

The audit API exposes what the HR UI needs without leaking internal database
structure. The revert endpoint may be refined during API contract design.

### 10.3 Bulk import

```text
POST /api/salary-imports
GET  /api/salary-imports
GET  /api/salary-imports/:id
```

The frontend polls import status initially. A WebSocket/SSE progress mechanism
is not required for the initial implementation.

`POST /api/salary-imports` returns the import id, not a processing result: it
creates the import, uploads the CSV to S3 and enqueues the job (§8.1). The
uploaded file is referenced by `s3_object_key` and is not exposed to the client.

## 11. Reporting

Reports use database-level aggregation rather than loading salary records into
Ruby memory. To be implemented, per
[`REQUIREMENTS.md`](REQUIREMENTS.md) §3.7:

```text
Average salary by department
Total payroll by country
Employee count by department
Employee count by country
Salary distribution
Salary trends
```

Queries must apply explicit currency semantics: the application must not
aggregate USD, EUR, GBP and so on into a single monetary total without an
explicit conversion strategy. Monetary reports therefore join to the employee to
resolve the currency, and group or split by it — for example, total payroll by
country is reported per currency rather than as one combined figure.

## 12. Testing Structure

The workflow that produces these tests is defined in the
[`README`](../README.md); this section defines what is covered and where.

### 12.1 Cucumber

Cucumber describes business behaviour.

```text
features/
├── employee_directory.feature
├── salary_management.feature
├── salary_history.feature
├── bulk_salary_management.feature
└── salary_reporting.feature
```

```gherkin
Scenario: HR corrects a historical salary
  Given an employee has a salary of 50000 USD effective from 2025-01-01
  When the HR Manager corrects the salary to 52000 USD
  Then the salary for 2025-01-01 should be 52000 USD
  And the previous value should remain available in the audit history
```

```gherkin
Scenario: An old salary import is rejected
  Given an employee's latest salary is effective from 2026-01-01
  When the HR Manager imports a salary effective from 2025-01-01
  Then the imported salary should not overwrite the existing salary
  And the row should be reported as skipped
```

### 12.2 RSpec

RSpec covers:

- Model validations
- Salary service rules
- Effective-date logic
- Stale import protection
- No-op detection
- PaperTrail behavior
- Revert behavior
- CSV row validation
- Sidekiq job behavior
- API request behavior
- Reporting queries
- Edge cases

## 13. Secure Implementation Practices

Authentication and RBAC are out of scope for the initial assessment, but the
implementation still follows secure coding practices:

- Strong parameter / API input validation
- File type and size validation on upload
- Safe CSV parsing
- SQL parameterization
- Brakeman checks
- No secrets in source control
- Controlled error responses

Production deployment must add authentication and authorization before exposing
salary information to real users.
