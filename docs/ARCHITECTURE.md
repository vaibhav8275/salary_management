# ACME Employee Salary Management — Architecture

> **Scope of this document:** the shape of the solution and why it was chosen.
> Product scope and business rules live in
> [`REQUIREMENTS.md`](REQUIREMENTS.md); schema, services, endpoints and test
> structure live in [`LLD.md`](LLD.md).

## 1. Architecture Goal

Build a maintainable salary management application for approximately 10,000
employees while keeping the architecture proportional to the problem.

The solution is a **Next.js frontend, a Rails API, a PostgreSQL database and
Sidekiq background processing**, deployed containerized to AWS EKS.

The design rule applied throughout: measure first, add infrastructure only when a
requirement demands it.

## 2. System Context

```text
                     ┌─────────────────────┐
                     │     HR Manager      │
                     └──────────┬──────────┘
                                │
                                ▼
                     ┌─────────────────────┐
                     │     Next.js UI      │
                     └──────────┬──────────┘
                                │ HTTPS / JSON
                                ▼
              ┌──────────────────────────────────┐
              │           Rails API              │
              │                                  │
              │  Employee Management             │
              │  Salary Management               │
              │  Salary History                  │
              │  Reporting                       │
              │  Bulk Import                     │
              └────────┬───────────────┬─────────┘
                       │               │
                       ▼               ▼
              ┌─────────────┐   ┌─────────────┐
              │ PostgreSQL  │   │   Sidekiq   │
              │             │   │   Workers   │
              └──────┬──────┘   └──────┬──────┘
                     │                 │
        reference    │                 │  background jobs
        data cache   ▼                 ▼
              ┌──────────────────────────────────┐
              │            Redis                │
              └──────────────────────────────────┘
                                       │
                                       ▼
                              Bulk Salary Processing
```

## 3. Architectural Style

### 3.1 Monolith

The Rails backend is a single deployable application with clear internal
modules:

```text
Employee
Salary
SalaryImport
Reporting
Currency
Audit
```

These are application boundaries — code and naming boundaries within one
process and one database — not independently deployed services.

### 3.2 Why not microservices

The requirement is approximately 10,000 employees and does not require
independently scalable distributed services. Microservices would introduce:

- Network communication between business capabilities
- Service discovery
- Distributed tracing
- Deployment complexity
- Data ownership complexity
- Distributed failure modes

…all without a demonstrated business requirement.

**Tradeoff accepted:** one codebase and one database mean a single deployment
unit and no cross-service consistency problems, at the cost of coarser
independent scaling. Bulk import is the one genuinely long-running workload, and
it is isolated in background workers rather than split into a service.

The architecture can be decomposed later if a concrete scaling or organizational
requirement emerges.

## 4. Component Responsibilities

### 4.1 Frontend — Next.js

Next.js is responsible for:

- The HR user interface
- Employee search and filter UI
- Salary management screens
- Salary history
- Audit history
- Bulk import workflow
- Reporting screens
- API communication with the Rails API

The frontend does not access PostgreSQL directly:

```text
Next.js → Rails API → PostgreSQL
```

All data access, validation and business rules stay on the server.

### 4.2 Backend — Rails API

The Rails API exposes explicit HTTP APIs. Controllers stay thin; the internal
layering is:

```text
Controller
    ↓
Application/Domain Service
    ↓
Model / Repository-level database operations
    ↓
PostgreSQL
```

Business rules — salary effective-date handling, stale-import protection, no-op
detection — live in the service layer. They are implemented once and reused by
controllers, background jobs and reporting queries, rather than duplicated across
those entry points.

### 4.3 Background processing — Sidekiq

Sidekiq owns every long-running task. The request that starts a bulk import
creates an import record, enqueues a job and returns; all CSV reading,
validation, batching and persistence happens in the worker.

Sidekiq's only persistent dependency is the same PostgreSQL database the API
uses, which keeps the deployment to two services instead of adding a broker.

### 4.4 Data store — PostgreSQL

PostgreSQL is the single system of record and is sufficient for the stated scale
of approximately 10,000 employees. It also carries integrity: uniqueness,
foreign keys and non-negative amounts are enforced in the database, not only in
application code.

### 4.5 File storage — AWS S3

Uploaded CSV files are stored in S3 rather than on application disk, so that the
API pod and the worker do not need to share a filesystem and the worker can read
the file asynchronously. This is Active Storage's own S3 service
(`config/storage.yml`), not a hand-rolled client: the application does not build
S3 keys, sign requests, or clean up orphaned objects, and the same code path runs
against a disk service in test and local environments.

**The import operation owns the file, not the request.** The CSV is attached to
the import record, so the database holds the link to it. The background job is
then handed only the import id and resolves the attachment through the database:

```text
S3  (Active Storage service)
 │  has_one_attached :csv_file
 ▼
SalaryImport  ──import_id──▶  Sidekiq Job  ──updates──▶  SalaryRecord
                                                              │
                                                  changes recorded by
                                                              ▼
                                                        PaperTrail
```

Nothing about the file travels in the job payload, so a job can be retried or
re-enqueued without re-uploading anything, and the API and worker need no shared
state beyond the database they already both use.

The original file is not retained beyond processing in the initial
implementation. Field-level detail is in [`LLD.md`](LLD.md) §2.6.

### 4.6 Reference data cache — Redis

Three tables — `currencies`, `countries` and `departments` — are read on nearly
every request and written almost never. They are reference data: valid currency
values, the countries salaries may be paid in, and the departments that exist.
Every employee row needs a department name and a country name, and every salary
needs the currency of the employee's country.

That makes them the one part of the data set worth keeping permanently in Redis
rather than re-reading from PostgreSQL:

```text
employees.country_id  ─┐
employees.department_id ─┤
                        ▼
              ┌─────────────────┐        miss
              │     Redis       │ ─────────────────► PostgreSQL
              │ reference_data: │ ◄─────────────────  read + repopulate
              │ countries       │
              │ departments     │
              │ currencies      │
              └─────────────────┘
```

**Why this shape.** A single cached value resolves the whole
`employee → country → currency` path, because a country embeds its currency. A
page of 25 employees therefore renders from one Redis round trip instead of a
join per row or a lookup map assembled per request.

**What is deliberately not cached.** `job_titles` (LLD §2.9) is a fourth
reference table but it is not in Redis. The cache pays for itself because the
three cached tables sit on the salary/currency path — read on nearly every
request, grouped by in every report. A title never decides a monetary amount or
a report group; the employee directory is its only reader, so the joins it adds
per page are not worth a cache key and its invalidation rules. It stays a plain
keyed table.

**Why it is permanent.** These rows are not volatile: they change when reference
data is added, not as a side effect of using the system. An expiring cache would
reintroduce the database reads it exists to avoid. The cache is instead reloaded
explicitly by the write path, and **a read that misses, or a Redis that is
unreachable, falls back to PostgreSQL** — the cache is an optimisation and must
never be the reason a request fails. PostgreSQL remains the single system of
record; Redis holds a copy for reads only.

**No new infrastructure.** Redis is already required by Sidekiq, so this adds no
new stateful service to the deployment; it is a second use of one that is
already there.

The cache layout, invalidation rules and read/write entry points are in
[`LLD.md`](LLD.md) §2.8.

## 5. Key Flows

### 5.1 Interactive salary update

```text
HR Manager
    ↓
Next.js
    ↓
PATCH /api/v1/employees/:id/salary
    ↓
Rails Controller
    ↓
Salary Service
    ↓
SalaryRecord
    ↓
PaperTrail
```

The service applies the effective-date rules and skips audit versions when no
tracked value changed.

### 5.2 Bulk import

```text
HR Manager
    ↓
Upload CSV
    ↓
Next.js
    ↓
Rails API
    ├── Create import record
    ├── Upload CSV → S3
    └── Enqueue Sidekiq job (import id)
            ↓
         Sidekiq
            ↓
         Read CSV from S3, process in batches
            ↓
         Salary Service
            ↓
         SalaryRecord
            ↓
         PaperTrail when values change
```

**Both paths converge on the same salary service**, so a salary written by CSV
and a salary written by a form cannot end up under different rules. The
row-level decision procedure and batch/transaction strategy are specified in
[`LLD.md`](LLD.md).

## 6. Domain Boundaries

Each concern has exactly one component responsible for it. This table is the
test for any proposed change: if a new field does not clearly belong to a row on
the left, it is probably in the wrong place.

| Concern                        | Responsible component |
| ------------------------------ | --------------------- |
| Original CSV                   | S3                    |
| Import operation and its outcome | `SalaryImport`        |
| Background processing          | Sidekiq               |
| Salary business data           | `SalaryRecord`        |
| Failed rows                    | `SalaryImportError`   |
| Valid currencies, countries, departments | PostgreSQL, cached in Redis (§4.6) |
| Job titles (roles an employee holds)     | PostgreSQL, plain keyed table (§4.6) |
| Who/what changed a salary      | PaperTrail            |
| Which import caused a change   | PaperTrail metadata   |

Three concepts are deliberately kept separate, because merging them is the most
common way a system like this loses either its history or its accountability:

| Concept           | Responsibility                                                                 |
| ----------------- | ------------------------------------------------------------------------------ |
| **Salary record** | The business history: what salary was effective for this employee, and from when |
| **Audit version** | The change history: what changed, when, by whom, and from which operation        |
| **Import record** | The bulk operation: one uploaded file, its status, counts and outcome           |

Consequences of the separation:

- A PaperTrail version is a side effect of a change, never the system of record
  for salary.
- Bulk-operation metadata lives on the import record and on audit versions, never
  on the salary rows it happened to touch — so a salary record is never labelled
  as belonging to one import when several may have written to it.
- These responsibilities must stay independent as the system grows.

The field-level design of these entities is in [`LLD.md`](LLD.md).

## 7. Cross-Cutting Strategy

### 7.1 Data consistency

Prefer database constraints over application-only assumptions. The application
layer provides friendly errors; the database guarantees correctness. Concrete
constraints are listed in [`LLD.md`](LLD.md).

Employee number uniqueness relies on the employee primary key being the employee
number, so uniqueness is structural rather than an extra index.

### 7.2 Performance

The primary strategies for the 10,000-employee dataset are:

- Database indexes on search and filter columns
- Pagination everywhere a collection is returned
- Server-side filtering and search
- Database-level aggregation for reports
- Asynchronous, batched CSV processing
- A permanent Redis cache for the small reference tables — currencies, countries
  and departments — so the names and currency each employee row needs are not
  read from PostgreSQL on every request (see §4.6)
- Never loading all employees into application memory

Concrete indexes, batch size and the performance validation plan are in
[`LLD.md`](LLD.md).

### 7.3 Audit storage

PaperTrail is not an event log. Only real changes to tracked attributes create
versions, which bounds audit-table growth when the same file is imported
repeatedly. A future production deployment may introduce an explicit audit
retention policy.

### 7.4 Security

Compensation data is sensitive, so the API is closed to unauthenticated callers
at the boundary. Devise owns the credentials and the account, devise-jwt turns a
successful sign-in into a stateless token, and Warden's `authenticate_user!` guard
on `ApplicationController` is the single place a request is checked — so adding an
endpoint does not add a second place to forget.

The parts that are deliberately absent are the parts that need requirements of
their own: there is no role model, no per-record policy, and no sign-out. Because
tokens are not revocable, a leaked token stays valid until it expires; that is
acceptable for an account created by an operator and not for a workforce-wide
rollout, which is why revocation and roles are named as future work rather than
half-built here.

Before exposing the system to real users, production architecture should also
include:

- HTTPS
- Secret management
- Database access controls
- Audit access controls
- Secure file upload handling
- API input validation
- Security monitoring

Implementation-level secure-coding practices are in
[`LLD.md`](LLD.md); the scope decision itself is in
[`REQUIREMENTS.md`](REQUIREMENTS.md).

## 8. Deployment Architecture

```text
GitHub
   ↓
CI/CD Pipeline
   ↓
Container Build
   ↓
Container Registry
   ↓
AWS EKS
   ├── Next.js
   └── Rails API
        ├── Sidekiq
        └── Redis ──► PostgreSQL
```

The Rails API and Sidekiq share an image; the process role is what differs.
Uploaded files are held in S3. Redis is the shared state of the two Rails
processes: Sidekiq's job queues and the reference data cache (§4.6) — one
stateful service, not two. AWS services used: S3, EKS, EC2, RDS and ElastiCache
(or an equivalent managed Redis).

The exact networking, secrets management, ingress and scaling configuration are
deployment implementation details, not architectural commitments.

## 9. Architectural Principles

1. Keep the architecture proportional to the requirement.
2. Keep business rules in the domain/application layer.
3. Keep controllers thin.
4. Keep salary history separate from audit history.
5. Keep bulk-operation metadata separate from salary records.
6. Use the same salary rules for UI and CSV processing.
7. Prefer database constraints over application-only assumptions.
8. Use asynchronous processing where work is long-running.
9. Measure before introducing distributed infrastructure.
10. Preserve audit history rather than silently rewriting it.
