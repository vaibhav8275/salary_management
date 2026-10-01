# ACME Employee Salary Management

A web-based employee salary management system for ACME HR, designed to replace
spreadsheet-based salary management for approximately 10,000 employees across
multiple countries.

The application gives an HR Manager a single place to search employees, review
and update compensation, maintain salary history, run bulk salary updates from
CSV, and understand pay through reporting and queries.

## Project Status

Built and deployed. The Rails API and Next.js frontend both run on a single EC2
instance; the database is seeded with 10,000 employees.

| | |
| --- | --- |
| Backend | Rails 8 API, deployed with Kamal |
| Frontend | Next.js, separate repository |
| Database | PostgreSQL on RDS, 10,000 employees seeded |
| Suite | 506 RSpec examples + 77 Cucumber scenarios, all passing |
| Storage | S3 for uploaded CSVs; Redis for job queues and reference-data cache |
| Health | `GET /up` → 200 |

Development followed a developer-led, AI-assisted TDD/BDD workflow: business
behaviour was captured as Cucumber/Gherkin scenarios first, then automated tests,
then implementation.

## Documentation

| Document                                  | Owns                                                                        |
| ----------------------------------------- | --------------------------------------------------------------------------- |
| [`docs/REQUIREMENTS.md`](docs/REQUIREMENTS.md) | What the system must do: scope, business rules, data requirements, constraints, assumptions, exclusions, success criteria |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | The shape of the solution: architectural style, components, domain boundaries, cross-cutting strategy, deployment topology, tradeoffs |
| [`docs/LLD.md`](docs/LLD.md)                   | How it is built: entities and fields, constraints, indexes, salary and import rules, services, API surface, test structure |
| [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md)     | How it reaches a server: deployment topology, roles, secrets and IAM, first deploy, verification, backup posture, day-two operations |

How to read the set:

- **Requirements** explains *why* and *what*. A rule stated there is a product
  commitment.
- **Architecture** explains *how the solution is shaped and why those choices
  were made*.
- **LLD** explains *how it is implemented* — the concrete, changeable detail.
- Anything implemented differently should change the LLD, not the requirements
  or the architecture, unless the design itself is wrong.
- Each fact is documented once, in the document that owns it. Other documents
  link to it instead of restating it.

## Technology at a Glance

**Backend**

- Ruby on Rails API
- PostgreSQL
- RSpec
- Cucumber
- PaperTrail
- Sidekiq
- RuboCop
- Brakeman
- `rack-cors`

**Frontend**

- Next.js (App Router)
- TypeScript
- Tailwind CSS, with in-repo components in `src/components`

**Delivery**

- Git / GitHub with meaningful incremental commits
- Automated CI checks
- Docker where useful for local development
- Containerized deployment to EC2 with Kamal
- AI-assisted development using project-specific instructions
- Next.js DevTools MCP for frontend development where appropriate

How each technology is used is described in
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## What the System Does

- **Employee directory** — search by employee ID, name or job title, filter by
  department, country and job title, paginate results, and view employee details
  across roughly 10,000 employees.
- **Salary management** — view current salary, add and edit salary records across
  effective periods, and keep salary history instead of overwriting it.
- **Audit history** — each salary record carries its own change log, so you can
  see what changed to *that* period, when, and who changed it, without destroying
  the audit trail. Unintended changes are fixed by editing the record.
- **Bulk salary management** — upload CSV salary changes, process them
  asynchronously in batches, report invalid and skipped rows, and never let an
  old export overwrite newer salary data.
- **Reporting and queries** — average salary by department, salary distribution,
  total payroll by country, salary trends over time, filtered by date range,
  department and country.

The authoritative scope, including what is deliberately excluded, is in
[`docs/REQUIREMENTS.md`](docs/REQUIREMENTS.md).

## Working in This Repository

### Development workflow

```text
Requirement
     ↓
Cucumber / Gherkin specification
     ↓
RED — failing automated test
     ↓
GREEN — minimal implementation
     ↓
REFACTOR
     ↓
Regression tests
```

Cucumber/Gherkin describes important business behaviour as an executable
specification:

```gherkin
Scenario: HR manager updates an employee salary
  Given an employee has a salary of 50000 USD
  When the HR manager changes the salary to 60000 USD
  Then the employee's current salary should be 60000 USD
  And the previous salary should remain in salary history
```

RSpec provides fast, deterministic lower-level tests for domain behaviour,
validations, services, API requests and edge cases. The feature and spec layout
is defined in [`docs/LLD.md`](docs/LLD.md).

### AI-assisted development

AI is used as a development assistant, not as an autonomous developer.

The developer remains responsible for:

- Requirements
- Product decisions
- Architecture
- LLD
- TDD direction
- Business rules
- Code review
- Test review
- Tradeoffs
- Final implementation decisions

AI may assist with:

- Exploring implementation approaches
- Identifying edge cases
- Suggesting tests
- Writing implementation code
- Debugging
- Refactoring
- Reviewing code

The Cucumber specifications provide an explicit behavioural contract before
implementation.

### Development sequence

```text
Requirements
     ↓
Cucumber / BDD specifications
     ↓
Architecture
     ↓
Low-Level Design
     ↓
RSpec / automated tests
     ↓
Rails API implementation
     ↓
Next.js frontend
     ↓
10,000 employee seed data
     ↓
Deployment
```

### Development principles

- Keep the design proportional to the stated problem.
- Prefer simple, maintainable solutions over unnecessary complexity.
- Use database constraints and application validation where appropriate.
- Keep API contracts explicit.
- Keep tests deterministic and easy to understand.
- Make meaningful incremental Git commits.
- Do not change specifications merely to make implementation tests pass.
- Measure performance against the stated 10,000-employee dataset rather than
  prematurely introducing distributed infrastructure.
- Document design tradeoffs and performance considerations as they are made.

### Expected artifacts

The repository is expected to contain requirements, architecture, LLD, Cucumber
specifications, automated tests, design tradeoffs, performance considerations,
deployment documentation, and Git history plus AI prompts showing incremental
development.

### Deployment

The backend deploys with a destination, so its proxy service is registered as
`salary_management-web-production`:

```bash
kamal deploy -d production
```

The frontend is a separate repository and deploys without one:

```bash
kamal deploy
```

Adding a destination to an app that had none registers a *second* proxy service
rather than renaming the first, and two catch-alls on one host fail with
`host settings conflict with another service`. See
[`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md) §4 before changing this.