# Deployment

How the two applications reach the server and what has to be true before they
serve traffic. Operational mechanics only — field-level detail stays in
[`LLD.md`](LLD.md), entity meaning in [`REQUIREMENTS.md`](REQUIREMENTS.md).

**Status: deployed and running.** Two applications, one EC2 instance, one
Elastic IP.

## 1. What runs

| | Repository | Deployed as | Proxy service |
| --- | --- | --- | --- |
| Rails API | `salary_management` | `kamal deploy -d production` | `salary_management-web-production` |
| Next.js frontend | `salary_management_next` | `kamal deploy` (no destination) | `salary-management-web-web` |

Both live on the same host and share it through `kamal-proxy`, which routes by
path rather than by hostname.

```
                          ┌──────────────────────────────────────┐
    developer ───────────▶│  EC2 instance (Ubuntu 24.04)          │
      kamal deploy        │                                      │
                          │  kamal-proxy  :80                     │
                          │    ├── /api/v1  /up  /api-docs  ──────┼──▶ Rails web
                          │    └── /*                            │
                          │                            ─────────┼──▶ Next.js web
                          │                                      │
                          │  salary_management-web-production     │
                          │  salary_management-job-production    │  same image, bin/jobs
                          │                                      │
                          │  salary_management-redis              │  redis:7-alpine
                          └──────────────────────────────────────┘
                                    │                    │
                        ┌───────────┴──────┐   ┌─────────┴──────────┐
                        │ RDS PostgreSQL   │   │ S3 (CSVs)          │
                        │ salary_...prod  │   │ salary-management-1│
                        └──────────────────┘   └────────────────────┘
```

`web` and `job` run **the same image**; only the command differs. A long CSV
import cannot block an API request, and a worker crash cannot take the API down.

## 2. Roles and routing

The API's `proxy.path_prefixes` are `/api/v1`, `/up`, `/api-docs`. The frontend
declares none, so it is the catch-all.

That split only works because **neither** service sets a `host:` key. Omitting it
makes `kamal-proxy` match any `Host` header, which is what a bare-IP URL needs — a
request to `http://<EIP>/` arrives as `Host: <EIP>` and has to match something.
Setting `host: "*"` does **not** work: the asterisk registers as a literal
hostname, every request 404s at the proxy, and both containers still report
healthy.

`/up` is deliberately inside the Rails prefixes rather than the catch-all, so the
health check is not answered by the frontend.

## 3. Configuration

`config/deploy.yml` is rendered through ERB before Kamal parses it. The host, AWS
account, frontend origin, and Redis URL come from `.kamal/secrets.production`
when a destination is given, and from `.env` otherwise:

```ruby
Dotenv.overload(".env") unless ENV["KAMAL_DESTINATION"]
```

Every value is required. A missing one raises naming the variable rather than
producing a half-configured container.

| Value | Source | Notes |
| --- | --- | --- |
| `EIP` | secrets / `.env` | The Elastic IP. Also the only server in `servers.web` and `servers.job` |
| `AWS_ACCOUNT` | secrets / `.env` | Builds `registry.server` as `<account>.dkr.ecr.us-east-1.amazonaws.com` |
| `FRONTEND_ORIGIN` | secrets / `.env` | Passed as a `clear` env value, read by the CORS initializer |
| `REDIS_URL` | secrets / `.env` | The accessory's container name on the shared Docker network |
| `SECRET_KEY_BASE` | `env.secret` | Generated once; never rotated by a deploy |
| `JWT_SECRET` | `env.secret` | Separate from `SECRET_KEY_BASE` so either rotates alone |
| `SALARY_MANAGEMENT_DATABASE_{USERNAME,PASSWORD,NAME}` | `env.secret` | |
| `DB_HOST`, `DB_PORT` | `env.secret` | RDS endpoint |
| `S3_BUCKET` | `env.secret` | Must match `config/storage.yml` |
| `KAMAL_REGISTRY_PASSWORD` | `.kamal/secrets-common` | `$(aws ecr get-login-password …)`, refreshed each deploy |

Two rules are worth keeping:

**`REDIS_URL` is the container name**, not `localhost`. Inside a container,
`localhost` is that container. A `localhost` default produces a worker that never
sees a job, with no error anywhere — it looks healthy and idle.

**The Redis accessory has no `port:` mapping.** It is reachable only on the
internal Docker network. Publishing `6379` would bind it on `0.0.0.0` and expose
the cache and the job queue to the network.

## 4. Deploying

```bash
# Confirm the config resolves before touching a server. Prints topology, not
# secret values.
bin/kamal config -d production

# Deploy.
bin/kamal deploy -d production
```

The frontend is a separate repository with its own `config/deploy.yml`:

```bash
kamal config
kamal deploy
```

### Destinations change proxy service names

Kamal names each proxy service after `[service, role, destination]`, with
`destination` nil when none is given. The same app therefore registers under a
different name once a destination is added, and the old registration is **not**
replaced — it is joined by a second one. Two catch-alls on the same host fail:

```
Error: host settings conflict with another service
```

Puma logs `Listening on http://0.0.0.0:3000`, so the image is fine and the
message reads like an unrelated crash. It is not: it fails on the
`kamal-proxy deploy` line, one step earlier.

Before adding a destination to an app that had none:

```bash
docker exec kamal-proxy kamal-proxy list                    # what is registered
docker exec kamal-proxy kamal-proxy remove <service>-<role> # the name WITHOUT the suffix
```

The same applies to secrets. Kamal reads `.kamal/secrets-common` for every
invocation and layers the destination file on top, so `.kamal/secrets` is read
**only** when no destination is given. A value committed there works until
someone types `-d production`, then fails with
`Secret '…' not found in .kamal/secrets.production`. Shared values belong in
`.kamal/secrets-common`, which the gitignore pattern `.kamal/secrets.*` does not
match — that file holds only `$(...)` recipes and is meant to be committed.

## 5. Verifying a deploy

```bash
bin/kamal details -d production                # containers and health
bin/kamal logs -f -d production                # web
bin/kamal logs -f -d production -r job         # worker — must not be silent
bin/kamal app exec -d production -r job "ps -o pid,args"
```

Checks in order:

1. **Health.** `GET /up` returns 200. It sits outside JWT authentication, so it
   needs no token. A protected route must answer 401 without one — if it answers
   200, authentication is not enforced.
2. **The worker is alive.** The failure that matters most, and the one a web-only
   check misses. If `job` is down, imports still return 200 and still create
   records; they simply never leave `pending`. Confirm by enqueueing an import and
   watching the record reach `completed`.
3. **Redis is shared.** Both roles must agree on `REDIS_URL`. A mismatch enqueues
   jobs nothing consumes, silently.
4. **S3 round trip.** An import reaching `completed` proves Active Storage wrote
   and read an object. A boot with the bucket misconfigured still starts.
5. **The database is really remote.**
   `bin/kamal app exec -d production -r web "bin/rails runner 'puts ActiveRecord::Base.connection_db_config.configuration_hash[:host]'"`

## 6. Day-two operations

| Task | Command |
| --- | --- |
| Deploy | `bin/kamal deploy -d production` |
| Roll back | `bin/kamal rollback -d production <version>` |
| Redeploy same image | `bin/kamal redeploy -d production` |
| Tail web logs | `bin/kamal logs -f -d production` |
| Tail worker logs | `bin/kamal logs -f -d production -r job` |
| Rails console | `bin/kamal console -d production` |
| Shell | `bin/kamal shell -d production` |
| Inspect containers | `bin/kamal details -d production` |
| Prune old images | `bin/kamal prune -d production` |

Rollback reverts the image. **Schema changes are not rolled back.**

## 7. Data and what happens if it is lost

| State | Held in | If lost |
| --- | --- | --- |
| Salaries, employees, audit trail | RDS PostgreSQL | Restored by RDS automated backups and PITR. The only state that matters |
| Uploaded CSVs | S3 bucket | Objects are re-uploadable; the audit trail references them, so losing them breaks those links |
| Reference-data cache | Redis | Disposable. Repopulated from PostgreSQL on a miss |
| **Sidekiq queues** | **Redis** | **Not recoverable** |

The queue is the sharp edge. It lives in the `redis_data` volume on the EC2
instance and nothing replicates it. If the instance is replaced, queued jobs are
gone and a mid-flight import stays `pending` forever with nothing running it.
Acceptable while imports are rare; not acceptable if they become routine. The
fix that does not change the architecture is a sweeper that requeues stale
`pending` imports, so the system converges without operator action.

## 8. Current limitations

These are true today, not placeholders.

- **No TLS.** `ssl: false` and no hostname, so the app serves plain HTTP on the
  Elastic IP. The frontend's `COOKIE_SECURE` is correspondingly `false`; browsers
  silently discard a `Secure` cookie received over `http://`, which makes sign-in
  appear to succeed and then bounce back to the login page. Both must flip in the
  same change that introduces a hostname and a certificate.
- **One instance.** A single point of failure. Maintenance means downtime.
- **No monitoring.** Nothing alerts. Until something does, "the worker is silently
  down" is the most likely real outage, which is why step 5.2 is a deploy gate
  rather than a nicety.
- **No CI deploy.** `.github/workflows/ci.yml` runs the suite on every push;
  releases are manual.
- **`builder.context: .`** disables the git clone, because the image is built
  from the working tree rather than a commit. Drop it once the tree is clean if
  reproducible builds are wanted.

## 9. Traps worth remembering

- `bin/jobs` must call `Sidekiq::CLI.instance`, then `parse`, then `run` with no
  arguments. Passing `ARGV` to `run`, or skipping `parse`, raises at boot and the
  worker processes nothing.
- `config/database.yml` keeps an explicit `host` in the `production` block.
  Without it the pg gem falls back to a local socket and never reaches RDS.
- A missing `DB_HOST` fails at boot with a named `KeyError`, and so does a
  **blank** one — dotenv turns `KEY=` into an empty string, and an empty password
  produces a confusing authentication error much later.
- The Redis accessory uses `host:`. Without it, Redis deploys to the machine
  running `kamal`, which is the laptop.
- `bin/kamal config` is safe to paste. Its `--help` advertises "including
  secrets!", but against Kamal 2.12.0 it emits topology and no secret values.
  Secrets *are* visible inside a running container (`bin/kamal app exec -r web
  env`) and in anything that echoes a recipe's output.

## 10. Why `config/deploy.production.yml` is `{}`

That file is mandatory, not optional. Kamal raises an error when it is missing,
and the error names the exact path:

```
ERROR (RuntimeError): Configuration file not found in .../config/deploy.production.yml
```

From `kamal-2.12.0/lib/kamal/configuration.rb`, the destination file is required
and its absence is fatal:

```ruby
def load_config_file(file)
  if file.exist?
    template = File.read(file)
    rendered = ERB.new(template, trim_mode: "-").result
    YAML.send(:unsafe_load, rendered).symbolize_keys
  else
    raise "Configuration file not found in #{file}"
  end
end

def destination_config_file(base_config_file, destination)
  base_config_file.sub_ext(".#{destination}.yml") if destination
end
```

So `-d production` always looks for `config/deploy.production.yml`, and
`config/deploy.yml` alone is not enough.

### `{}` is the minimum that works

Kamal deep-merges the base config with the destination file, so the file has to
parse into a hash. Verified against 2.12.0:

| File content | `kamal config -d production` |
| --- | --- |
| absent | fails — `Configuration file not found` |
| zero bytes | **fails** — parses to `nil`, `deep_merge!` breaks |
| `# comment` only | **fails** — same reason |
| `{}` | resolves |

An empty file does not work, which is the counter-intuitive part. `{}` is not a
placeholder standing in for real settings; it is the smallest valid YAML document
that yields an empty hash, which merges harmlessly and leaves
`config/deploy.yml` fully in charge.

### What it is for

Nothing today. It is the extension point for per-environment overrides:

```yaml
# config/deploy.production.yml
env:
  clear:
    RAILS_LOG_LEVEL: info
```

The same pattern gives a `config/deploy.staging.yml` with a different host or
registry, and lets one environment change `app_port`, `path_prefixes` or replica
count without duplicating the base config.

The alternative to keeping it is deploying without `-d`, which works but drops
the `-production` suffix from the proxy service name and stops Kamal reading
`.kamal/secrets.production` — the file that currently supplies every required
value in §3.
