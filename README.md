# Miway CreditCore

A multi-tenant Elixir/Phoenix loan management system: application intake,
affordability/CRB checks, multi-level approval workflow, disbursement,
repayment scheduling and allocation, a double-entry general ledger,
collections/arrears/write-offs, KYC, audit logging and reporting.

## Status

All 18 items of the original engineering roadmap are implemented and
demoed live against a local dev database — see
[`docs/MIWAY_CREDITCORE_ARCHITECTURE.md`](docs/MIWAY_CREDITCORE_ARCHITECTURE.md)
for the domain model and [`docs/architecture/context_boundaries.md`](docs/architecture/context_boundaries.md)
for the current context map.

**This is a pilot candidate, not yet a completed pilot.** The application
boots and migrates cleanly as a production release, but no controlled
pilot (real organisation, real staff, real end-to-end loan journey, backup
restore drill, sign-off) has been run yet. Known open items before real
users touch it:

- Password-reset email/SMS delivery is not configured in production by
  default (tokens generate correctly; nothing sends them — see
  `MiwayCreditCore.Accounts.PasswordResetNotifier`).
- KYC files are encrypted and malware-scanned but stored on local disk;
  persistent storage, backup/restore, and key rotation are not yet
  operationally defined.
- ClamAV is a hard runtime dependency for KYC upload (the scanner fails
  closed when `clamscan` is absent) but is not yet listed as an install
  prerequisite anywhere but here and the deployment runbook.
- The customer portal is read-only; the `Notifications` context (email/SMS
  delivery, templates, queues) is a reserved, unbuilt boundary.

See [`docs/MIWAY_CREDITCORE_DEPLOYMENT_RUNBOOK.md`](docs/MIWAY_CREDITCORE_DEPLOYMENT_RUNBOOK.md)
for what's required to close these before a real pilot.

## Development setup

Requires Elixir `~> 1.17` (built against 1.17.3/OTP 26) and PostgreSQL 16.

```bash
mix deps.get
mix ecto.create
mix ecto.migrate
mix run priv/repo/seeds.exs      # dev-only demo accounts — see warning below
mix phx.server
```

Visit [`localhost:4000`](http://localhost:4000).

### Demo seed warning

`priv/repo/seeds.exs` and `priv/repo/seeds/add_test_accounts.exs` create
accounts with published, well-known passwords committed to source control.
Both **refuse to run outside `MIX_ENV=dev`/`test`** — never run them against
a real database. To bootstrap a real first administrator, use
`MiwayCreditCore.Release.create_platform_administrator/0` (see the
deployment runbook).

## Tests

```bash
mix test                              # full suite
mix compile --warnings-as-errors      # clean compile check
mix format --check-formatted
```

## Production deployment

See [`docs/MIWAY_CREDITCORE_DEPLOYMENT_RUNBOOK.md`](docs/MIWAY_CREDITCORE_DEPLOYMENT_RUNBOOK.md)
for the required environment variables, the Postgres SSL configuration,
the build → migrate → bootstrap-admin sequence, and the operational
prerequisites (ClamAV, KYC storage, backups) that must be in place before
a pilot.

## Security

This system handles customer PII, KYC documents, and financial records.
If you find a security issue, do not open a public GitHub issue — contact
the project maintainer directly.

## Licence

Proprietary — see [`LICENSE`](LICENSE). This is Miway Technology Limited's
confidential source code, not open source; the repository must remain
private. A customer/lending organisation's right to *use* a hosted
deployment is governed by a separate commercial licence agreement, not by
this repository or its contents.
