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
  ├── belongs_to :department
  ├── belongs_to :country
  ├── belongs_to :job_title
  └── has_one :currency, through: :country

SalaryRecord
  │
  ├── belongs_to :employee
  └── has_paper_trail

SalaryImport
  │
  ├── has_many :salary_import_errors
  └── tracks one bulk import operation

Country
  │
  ├── belongs_to :currency  (the currency salaries in this country are paid in)
  └── has_many :employees

Department
  │
  └── has_many :employees

JobTitle
  │
  └── has_many :employees

Currency
  │
  └── referenced by countries (authoritative source of a salary's currency)
```

`department`, `country` and `job_title` are reference tables rather than
free-text columns, and a currency belongs to a **country**, not to an employee.
An employee's salary currency is therefore reached as
`employee.country.currency`: the path is fixed by the data model, so an employee
cannot be paid in a currency their country does not use, and the currency of a
salary record cannot drift away from the employee's country. Likewise, a person's
role is a `job_title` row (§2.9) so that "Software Engineer", "software engineer"
and "Software  Engineer" cannot enter as three different roles and split a
title-based report.

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
| `Employee`            | Who the person is and how to find them; placed in a department, a job title and a country |
| `SalaryRecord`        | The complete compensation state effective from a date, in the currency of the employee's country |
| `Country`             | Where an employee works, and the currency they are paid in                   |
| `Department`          | Which part of the company an employee belongs to                             |
| `JobTitle`            | Which role an employee holds; one canonical spelling per role                 |
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
department_id
job_title_id
country_id
hire_date
created_at
updated_at
```

| Field          | Rails type | Null | Notes                              |
| -------------- | ---------- | ---: | ---------------------------------- |
| `id`           | `bigint`   |   No | Rails primary key; **serves as the employee number** |
| `first_name`   | `string`   |   No | Employee first name                |
| `last_name`    | `string`   |   No | Employee last name                 |
| `email`        | `string`   |   No | Employee email; add unique index   |
| `department_id`| `bigint`   |   No | FK → `departments.id`             |
| `job_title_id` | `bigint`   |   No | FK → `job_titles.id`              |
| `country_id`   | `bigint`   |   No | FK → `countries.id`                |
| `hire_date`    | `date`     |   No | Employee joining date              |
| `created_at`   | `datetime` |   No | Rails timestamp                    |
| `updated_at`   | `datetime` |   No | Rails timestamp                    |

Because `id` is the employee number, employee-number uniqueness is structural —
no separate uniqueness constraint is required.

**No currency column.** `employees` deliberately has no `currency_id`: a currency
is an attribute of a country (§2.3), so the employee's currency is
`employees.country_id → countries.currency_id`. The two things a free-text
`department`/`country` pair plus a separate `currency_id` got wrong — a
misspelled department entering the data, and a country whose currency disagreed
with the employee's — are both structurally impossible this way. The title is the
same kind of decision: `job_title_id` (§2.9) instead of a free-text `job_title`
column.

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

A currency is referenced by countries (§2.3), not by employees. One currency row
is shared by every country paid in it — `EUR` is referenced by both Germany and
France — so `code` is unique across the table while the reference back to
countries stays many-to-one (§2.3).

### 2.3 `countries`

```text
id
name
currency_id
created_at
updated_at
```

| Field         | Rails type | Null | Notes                                          |
| ------------- | ---------- | ---: | ---------------------------------------------- |
| `id`          | `bigint`   |   No | Rails default primary key                      |
| `name`        | `string`   |   No | Country name — United States, United Kingdom; unique |
| `currency_id` | `bigint`   |   No | FK → `currencies.id`; **the currency salaries in this country are paid in** |
| `created_at`  | `datetime` |   No | Rails timestamp                                |
| `updated_at`  | `datetime` |   No | Rails timestamp                                |

**The country owns the currency.** One row per country, one currency per country:
an employee's salary currency is whatever their country is paid in, and a country
has exactly one currency so there is never an ambiguity to resolve at read time.

**The reverse is many-to-one, not one-to-one.** Several countries share a single
currency row: Germany and France both point at the same `EUR` row — that is the
case in the seed data — because both are paid in the euro. So one country never
has two currencies, while one currency is used by as many countries as need it.
The currency row is never duplicated per country, which is what keeps
`currencies.code` unique (§2.2) and keeps a "total payroll by country" report
from emitting the same currency twice. This is why the association is
`Country belongs_to :currency` together with
`Currency has_many :countries, dependent: :restrict_with_error` — the
`has_many` runs from the currency to the countries using it, and says nothing
about a country having more than one currency.

`name` is unique because it is the key the directory filter and the reporting
group-by use, and because a country appearing twice under two spellings would
split a report in two.

Countries are reference data, not an editable field on the employee: adding a
country is a data change, and the API matches an incoming country by name against
this table.

### 2.4 `departments`

```text
id
name
created_at
updated_at
```

| Field         | Rails type | Null | Notes                                    |
| ------------- | ---------- | ---: | ---------------------------------------- |
| `id`          | `bigint`   |   No | Rails default primary key                |
| `name`        | `string`   |   No | Department name — Engineering, Sales; unique |
| `created_at`  | `datetime` |   No | Rails timestamp                          |
| `updated_at`  | `datetime` |   No | Rails timestamp                          |

`name` is unique for the same reason as `countries.name`: the directory filter
and the "average salary by department" and "total payroll by department" reports
group by it, and a duplicated or misspelled name would fragment both.

`currencies`, `countries`, `departments` and `job_titles` are the four reference
tables. The first three are cached permanently in Redis — see §2.8. `job_titles`
(§2.9) is the exception: it never decides a monetary amount or a report group, so
it is left uncached.

### 2.5 `salary_records`

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
salary record are denominated in the currency of the owning employee's country,
reached via `salary_records.employee_id → employees.country_id →
countries.currency_id`. The employee's country is the single authoritative
source; the currency is not duplicated per record, so it cannot drift between an
employee and their history.

The consequence to keep in mind: an employee's currency applies to their whole
salary history, including past periods, and it is a consequence of their country
rather than an independent choice. If a salary ever needed to be denominated in
something other than the employee's country currency — a relocation, a
secondment — a currency column would have to be added to `salary_records` as a
deliberate, later change rather than introduced implicitly.

### 2.6 `salary_imports`

```text
id
filename
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
| `status`            | `integer`  |   No | Rails enum, see §8.2                             |
| `total_records`     | `integer`  |   No | Total CSV rows                                   |
| `processed_records` | `integer`  |   No | Successfully processed rows, including no-op rows |
| `failed_records`    | `integer`  |   No | Rows that encountered processing errors          |
| `created_by`        | `bigint`   |   No | HR Manager / user identifier                     |
| `started_at`        | `datetime` |  Yes | When background processing starts                |
| `created_at`        | `datetime` |   No | Rails timestamp                                  |
| `updated_at`        | `datetime` |   No | Rails timestamp                                  |

`created_by` references the uploading user. Authentication (AU-1 … AU-5,
`REQUIREMENTS.md` §7) puts a `users` table in the schema, but authorization is
still out of scope, so this stays a plain identifier rather than a foreign key:
there is no role or permission to check it against.

**`SalaryImport` owns the uploaded file.** The CSV is an Active Storage
attachment (`has_one_attached :csv_file`), so the link between the import and its
file is a row rather than a string that has to be kept in step with a bucket.
That is what lets the API and the worker stay decoupled — the job is handed only
the import id and reads the attachment off the row it already has to write to —
and it is why the file cannot end up in S3 with no import pointing at it: the
controller builds the record and its attachment and saves them together, so a
file that fails validation leaves nothing behind.

The attachment is validated by the model on create: present, at most
`MAX_FILE_SIZE` (2 MB), `.csv` extension, and a content type a CSV is likely to
arrive as. The extension is the real test; the content-type list is permissive
because the same file is labelled `text/csv` by curl and
`application/vnd.ms-excel` by older Excel. Header and row semantics are *not*
model validation — a CSV whose header line is wrong is a recorded import failure
(§8.2), not a rejected upload, because FR-4.5 and FR-6.6 ask for failures to be
reported rather than to abort the request. The object is not retained beyond
processing in the initial implementation.

### 2.7 `salary_import_errors`

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

### 2.8 Reference data cache

`currencies` (§2.2), `countries` (§2.3) and `departments` (§2.4) are the three
reference tables that earn a cache. Each holds tens of rows, is written almost
never — the seeds or an occasional administrative correction — and is read on
nearly every request: the employee directory renders a department and a country
per row, salary detail renders a currency, and every report groups by one or more
of them.

That asymmetry is the whole justification for caching them permanently in Redis.
Resolving the same three tables through PostgreSQL means a join per row, or a
lookup map assembled per request; with the cache, a whole page of employees is
rendered from one Redis round trip.

Layout — one key per table, each holding a JSON array of row objects:

```text
reference_data:currencies   → [ { "id": 1, "code": "USD", "name": "US Dollar", "symbol": "$" }, … ]
reference_data:countries    → [ { "id": 1, "name": "United States", "currency": { "id": 1, "code": "USD", … } }, … ]
reference_data:departments → [ { "id": 1, "name": "Engineering" }, … ]
```

A country embeds its currency, so the `employee → country → currency` path
(§2.1, §2.3) resolves from a single cached value rather than a second lookup.

Four rules make the cache safe to keep permanently:

- **No expiry.** The keys are written without a TTL. These rows are not volatile
  data, so an expiring cache would buy nothing and would only reintroduce
  database reads.
- **Explicit invalidation.** Only a write path reloads the cache — the seeds, or
  an administrative change to a reference row — through a single reload that
  rewrites all three keys together. There is no partial invalidation to reason
  about because the three tables always move as a set.
- **The cache is an optimisation, never a dependency.** A miss, or a Redis that is
  unreachable, falls back to PostgreSQL and repopulates. A request must not fail
  because the cache is cold or Redis is down.
- **PostgreSQL stays authoritative.** Redis holds a copy for reads; reference
  data is never written to Redis directly.

Populated by `ReferenceData.reload!`; read through `ReferenceData.countries`,
`ReferenceData.departments` and `ReferenceData.currencies`, with the
name-to-id lookups the directory filters and CSV import need. The deployment
topology and the reasoning behind it are in
[`ARCHITECTURE.md`](ARCHITECTURE.md) §4.6 and §7.2.

`job_titles` is a fourth reference table that is deliberately **not** cached.
The criterion for the cache is being on the salary/currency decision path — read
on nearly every request and grouped by in every report. A title never affects a
monetary amount or a report group; the employee directory is its only reader, so
the few joins it adds per page are not worth a cache key and its invalidation
rules. It stays a plain keyed table.

### 2.9 `job_titles`

```text
id
title
created_at
updated_at
```

| Field        | Rails type | Null | Notes                                    |
| ------------ | ---------- | ---: | ---------------------------------------- |
| `id`         | `bigint`   |   No | Rails default primary key                |
| `title`      | `string`   |   No | Canonical role name — Software Engineer; indexed, not unique |
| `created_at` | `datetime` |   No | Rails timestamp                          |
| `updated_at` | `datetime` |   No | Rails timestamp                          |

A job title is reference data an employee belongs to, like a department but for
the person's role. Two rules keep one role as one row:

- **Normalization before validation.** The title is stripped and interior spaces
  are squeezed, so `"  Software   Engineer  "` is stored as `"Software Engineer"`.
- **Case-insensitive uniqueness.** A second row differing only by case is
  rejected, so `"SOFTWARE ENGINEER"` cannot become a sibling of
  `"Software Engineer"` and split a title-based report in two.

Unlike `departments.name` and `countries.name`, the uniqueness is **not** a
database constraint: PostgreSQL has no case-insensitive unique index without an
extension, and adding that extension is heavier than the protection is worth for
a write-almost-never table whose rows are validated on every write path anyway.
The database still enforces NOT NULL and the foreign key from `employees`
(§2.1, §3); the case-insensitive uniqueness lives in the model
(`validates :title, uniqueness: { case_sensitive: false }`, §2.9).

The `title` index is non-unique and exists for the name-to-id lookups — the
directory and any future CSV column that names a role. Reporting by title is
supported by the association (`Employee` joins/where through
`job_titles.title`), which is exactly how the department and country reports are
expressed.

### 2.10 `users`

```text
id
email
encrypted_password
created_at
updated_at
```

| Field                | Rails type | Null | Notes                                       |
| -------------------- | ---------- | ---: | ------------------------------------------- |
| `id`                 | `bigint`   |   No | Rails default primary key                    |
| `email`              | `string`   |   No | Sign-in address; unique                     |
| `encrypted_password` | `string`   |   No | bcrypt digest — the password is never stored |
| `created_at`         | `datetime` |   No | Rails timestamp                             |
| `updated_at`         | `datetime` |   No | Rails timestamp                             |

The account is the whole of the authentication model (AU-1 … AU-5,
`REQUIREMENTS.md` §7), and its narrowness is the point: no role, no permissions,
no token column, no profile. Two columns are stored because signing in needs
exactly two things, and everything a caller is allowed to do is the same for
every account.

Rows are created by an operator (`bin/rails auth:create_hr_user`) rather than by
the API, so there is no `registerable` module and no sign-up endpoint. There is
no `rememberable` or `trackable` state either: the session is a stateless JWT,
so a token is either parseable and unexpired or it is not, and there is nothing
server-side to expire. Uniqueness of `email` is a database constraint, since a
sign-in looks the account up by that column and two rows would make the lookup
ambiguous.

## 3. Data Integrity

Use database constraints where practical; application validations provide the
friendly errors.

```text
employees.country_id          → FOREIGN KEY → countries.id
employees.department_id       → FOREIGN KEY → departments.id
employees.job_title_id        → FOREIGN KEY → job_titles.id, NOT NULL
countries.currency_id         → FOREIGN KEY → currencies.id
salary_records.employee_id     → FOREIGN KEY → employees.id
salary_records.base_salary     → non-negative, required
salary_records.bonus           → non-negative, required
salary_records.allowance       → non-negative, required
salary_records.effective_date  → required
```

Currency validity is enforced once, on the country. Because salary records
inherit currency through the employee and its country, no separate currency
constraint is needed on `salary_records`.

```text
UNIQUE (employee_id, effective_date)
UNIQUE (currencies.code)
UNIQUE (countries.name)
UNIQUE (departments.name)
```

The unique employee/effective-date pair prevents one employee from accidentally
holding two salary records for the same effective period — which is what makes
the "one record per period" rule in §5 enforceable rather than merely
conventional. The unique reference-data names prevent the same department or
country existing twice under one name, which would split a report in two (§2.3,
§2.4).

`job_titles` is the one reference table whose uniqueness cannot be a database
constraint: PostgreSQL has no case-insensitive unique index without an extension.
The NOT NULL foreign key and the `title` index are in the database, and the
case-insensitive uniqueness itself is a model rule (§2.9).

## 4. Indexes

Initial indexes to consider:

```text
employees.department_id
employees.country_id
employees.job_title_id
employees.first_name
employees.last_name
job_titles.title
salary_records.employee_id
salary_records.effective_date
```

The `departments` and `countries` names are unique, because they are matched by
name in the directory filters and grouped by in reports (§2.3, §2.4). The
`job_titles.title` index is not unique: uniqueness is case-insensitive, which is
a model rule (§2.9), and the index serves the name-to-id lookups of the directory
and the CSV rows that name a role.

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
  └── apply_imported_salary
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

## 8. Bulk Import Processing

### 8.1 Request flow

```text
HR
 │
 │ Upload CSV
 ▼
Rails API
 │
 ├── Create SalaryImport with the CSV
 │  attached and validated (§2.6)
 │
 └── Enqueue Sidekiq job with salary_import_id
        ↓
     Sidekiq Worker
        ↓
     Read the CSV off the import
        ↓
     Process each row
```

The API does not synchronously process a large CSV. The job is enqueued with the
import id alone — `SalaryImportJob.perform_async(salary_import.id)` — and the
worker finds the file through the import's attachment. Nothing about the
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
Load SalaryImport, read the CSV off its attachment
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

## 9. API Surface

Conceptual endpoints; exact naming and response contracts are finalized during
implementation.

### 9.1 Employees and salary

```text
GET   /api/v1/employees
GET   /api/v1/employees/:id
GET   /api/v1/employees/:id/salary
GET   /api/v1/employees/:id/salary/history
PATCH /api/v1/employees/:id/salary/:salary_record_id
```

`GET /api/v1/employees` filters on `department`, `country` and `job_title`, each
an exact match on the reference row's label. `job_title` matches `job_titles.title`
rather than a `name` column: `JobTitle` labels its field `title` (§2.9), unlike
`Department` and `Country`. The three filters combine, and `search` covers the job
title as well as the employee's own columns, because the directory's search box
offers job title as a searchable field (FR-1.3).

### 9.2 Audit

```text
GET /api/v1/employees/:id/salary/audit
```

The audit API exposes what the HR UI needs without leaking internal database
structure. The response is **grouped by salary record**: one entry per record,
ordered by that record's most recent change, each holding only that record's own
versions. A flat list of every version cannot answer "what happened to *this*
record?", which is the question a per-record change log has to answer, so the
grouping is part of the contract rather than something the client re-derives.

### 9.3 Bulk import

```text
POST /api/v1/salary-imports
GET  /api/v1/salary-imports
GET  /api/v1/salary-imports/:id
```

The frontend polls import status initially. A WebSocket/SSE progress mechanism
is not required for the initial implementation.

`POST /api/v1/salary-imports` returns the import id, not a processing result: it
creates the import with the CSV attached and enqueues the job (§8.1). The
attachment is not exposed to the client. A file that fails validation — absent,
too large, wrong extension, or a content type no CSV arrives as — is a 422, and
because the record and its attachment are saved together it leaves no import row
and no uploaded file behind (§2.6).

### 9.4 Authentication

```text
POST /api/v1/auth/login
```

The one endpoint that does not require a token, since it is where a token comes
from. It verifies an email and password against `users` (§2.10) and, on success,
answers with the JWT in the `Authorization: Bearer` response header and
`{"data": {"email": "..."}}` as the body. The token is in the header because that
is where every later request looks for it; a body field would be a second place
to forget to read from.

Every `api/v1` endpoint above this one requires the header. There is deliberately
no sign-up, sign-out, or password reset route, and `devise_for` is mapped with
`skip: :all` so those routes are never generated by accident — an open
registration endpoint on a salary system is a much worse default than a missing
one.

## 10. Reporting

Reports use database-level aggregation rather than loading salary records into
Ruby memory. To be implemented, per
[`REQUIREMENTS.md`](REQUIREMENTS.md) §3.7:

```text
Average salary by department
Total payroll by country
Employee count by department
Employee count by country
Employee count by job title
Salary distribution
Salary trends
```

Queries must apply explicit currency semantics: the application must not
aggregate USD, EUR, GBP and so on into a single monetary total without an
explicit conversion strategy. Monetary reports therefore join to the employee to
resolve the currency, and group or split by it — for example, total payroll by
country is reported per currency rather than as one combined figure.

The head counts are non-monetary, so they attach no currency, and they accept all
three reference filters regardless of which dimension is being grouped: grouping by
country while filtering on department is a legitimate combination, so every
grouping joins `departments`, `countries` and `job_titles` rather than only the one
being reported.

The `job_titles` association (§2.9) supports a future title-based report — for
example "average salary for Software Engineer in USA" — with the same join
pattern: group through `employees.job_title_id`, apply the currency semantics
above, and the canonical title rows (§2.9) mean the report cannot split one role
across spellings. No such report is in scope yet; the head count above is the only
title-based query so far.

## 11. Testing Structure

The workflow that produces these tests is defined in the
[`README`](../README.md); this section defines what is covered and where.

### 11.1 Cucumber

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
Scenario: HR edits a historical salary
  Given an employee has a salary of 50000 USD effective from 2025-01-01
  When the HR Manager edits the salary to 52000 USD
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

### 11.2 RSpec

RSpec covers:

- Model validations
- Salary service rules
- Effective-date logic
- Stale import protection
- No-op detection
- PaperTrail behavior
- Per-record audit grouping
- CSV row validation
- Sidekiq job behavior
- API request behavior
- Reporting queries
- Edge cases
- The authentication boundary: login, the 401s, and the absence of the routes
  that are not supposed to exist (§9.4)

Request specs are signed in by default. `spec/support/authentication_helpers.rb`
attaches the bearer header to every request in an example, and an example that is
about the *absence* of a token says so with `anonymous_caller!` rather than
remembering to pass `headers:`. That keeps the boundary described once, in the
place that defines it, instead of in several hundred near-identical request
lines.

## 12. Secure Implementation Practices

Authentication and RBAC were out of scope for the initial assessment, but the
implementation still follows secure coding practices:

- Strong parameter / API input validation
- File type and size validation on upload
- Safe CSV parsing
- SQL parameterization
- Brakeman checks
- No secrets in source control
- Controlled error responses

Since then, authentication has been added at the API boundary (AU-1 … AU-5,
`REQUIREMENTS.md` §7; `ARCHITECTURE.md` §7.4) and authorization has not:

- `POST /api/v1/auth/login` verifies an email and password with Devise and
  returns a stateless JWT in the `Authorization: Bearer` response header. The
  account is created by an operator (`bin/rails auth:create_hr_user`), never by
  the API, so there is no public sign-up, sign-out, or password-reset endpoint.
- `authenticate_user!` guards `ApplicationController`, which covers every
  `api/v1` controller. Unauthenticated requests are answered with the same
  `{"errors": [...]}` envelope as every other failure (401, `unauthorized`)
  rather than a redirect, so a client never has to parse an HTML login page.
- The signing secret comes from `JWT_SECRET`, falling back to the Rails secret key
  base. It is never committed (`.env.example`, `.kamal/secrets`).
- Passwords are hashed with bcrypt, at the lower test cost.

Production deployment still needs authorization before exposing salary
information to real users, and needs token revocation if a leaked token has to
stop working before it expires.
