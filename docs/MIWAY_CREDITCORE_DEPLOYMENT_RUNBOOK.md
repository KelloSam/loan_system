# Miway CreditCore — Deployment Runbook

A checklist for deploying a real release, not a general Elixir/Phoenix
tutorial. Every step below was verified live against an actual
`mix release` build (Step 18), not just written from reading config.

## 1. Required environment variables

All read by `config/runtime.exs`, nothing here is invented:

| Variable | Required | Notes |
|---|---|---|
| `DATABASE_URL` | yes | `ecto://USER:PASS@HOST/DATABASE` |
| `SECRET_KEY_BASE` | yes | generate with `mix phx.gen.secret` |
| `PHX_HOST` | yes | the public hostname, e.g. `creditcore.miway.co.zm` |
| `PORT` | no | default `4000` |
| `POOL_SIZE` | no | default `10` |
| `PHX_SERVER` | yes | must be `true` for the release to actually listen |
| `KYC_ENCRYPTION_KEY` | yes | base64, 32 raw bytes — generate with `:crypto.strong_rand_bytes(32) \| Base.encode64()`. Encrypts KYC document bytes at rest (AES-256-GCM). Losing this key makes every stored KYC document permanently unreadable — back it up like a secret, separately from the database. |
| `MFA_ENCRYPTION_KEY` | yes | base64, 32 raw bytes — generate with `:crypto.strong_rand_bytes(32) \| Base.encode64()`. Encrypts every user's TOTP secret at rest (AES-256-GCM). **Must be a different value from `KYC_ENCRYPTION_KEY`** — never reuse it, so a compromise of one key never exposes the other secret domain. Losing this key makes every enrolled user's MFA unusable (they'd need to disable and re-enroll TOTP) — back it up like a secret, separately from the database and separately from `KYC_ENCRYPTION_KEY`. See §9a. |
| `KYC_UPLOAD_DIR` | yes | absolute path to a **persistent volume outside the release directory** — see §9. The release refuses to boot without it, specifically so this can't be silently forgotten and only discovered after the first deploy wipes uploaded documents. |
| `BACKUP_ROOT_DIR` | yes | absolute path to a **persistent volume outside the release directory** — same reasoning as `KYC_UPLOAD_DIR`. See §10. |
| `SMTP_HOST` | no | see §12. Password-reset email stays disabled (fails closed, logged server-side) until this is set — safe to boot and pilot without it, then turn delivery on later with no redeploy. |
| `SMTP_USERNAME`, `SMTP_PASSWORD` | only if `SMTP_HOST` is set | provider SMTP credentials. |
| `MAIL_FROM_ADDRESS` | only if `SMTP_HOST` is set | the `From:` address on outgoing mail — most providers require this to be a verified sender/domain. |
| `SMTP_PORT` | no | default `587` (STARTTLS) |
| `MAIL_FROM_NAME` | no | default `Miway CreditCore` |

## 2. Database SSL

`config/prod.exs` requires the database connection to be SSL-verified
against a real CA — this is not optional, and was a confirmed,
production-blocking bug fixed in Step 18 (bare `ssl: true` alone made
every connection attempt fail with a client-side option-validation
error, before ever reaching the server).

- **Managed Postgres with a publicly-trusted cert** (RDS, DigitalOcean,
  Render, Supabase, etc — the expected pilot target): no changes
  needed. `ssl_opts: [verify: :verify_peer, cacerts: :public_key.cacerts_get()]`
  uses OTP's bundled CA store and validates these out of the box.
- **Self-hosted Postgres with a private/self-signed CA**: replace
  `cacerts: :public_key.cacerts_get()` with
  `cacertfile: "/path/to/your-private-ca.pem"` in `config/prod.exs`.
  Never change `verify: :verify_peer` to `verify: :verify_none` — that
  defeats the point of SSL and should not be used even temporarily.
- **Known follow-up, not yet built**: `ssl_opts` doesn't automatically
  derive hostname verification from the connection URL — the
  certificate chain is verified against the trusted CA, but hostname
  matching isn't unless `customize_hostname_check`/SNI options are also
  set. Worth revisiting if a pilot's Postgres host ever needs to defend
  against a CA-trusted-but-wrong-host scenario specifically.

## 3. Build

```
mix deps.get --only prod
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix release
```

`assets.deploy` is not optional — it's what generates
`priv/static/cache_manifest.json` and the minified JS/CSS under
`priv/static/assets/`. Both are gitignored (regenerated per build, not
committed) and a release built without this step first genuinely ships
with zero CSS/JS — confirmed by actually building one.

## 4. Migrate

```
_build/prod/rel/miway_credit_core/bin/miway_credit_core eval "MiwayCreditCore.Release.migrate"
```

Mix isn't available inside a compiled release, so `mix ecto.migrate`
doesn't work here — `MiwayCreditCore.Release.migrate/0`
(`lib/miway_credit_core/release.ex`) is the release-safe equivalent.

## 5. Bootstrap the first admin

**Never run `mix run priv/repo/seeds.exs` or
`priv/repo/seeds/add_test_accounts.exs` against this database** — both
hardcode accounts with published, well-known passwords and refuse to
run under `MIX_ENV=prod` for exactly this reason.

Instead:

```
ADMIN_EMAIL=you@realdomain.com ADMIN_PASSWORD='a-real-strong-password' \
  _build/prod/rel/miway_credit_core/bin/miway_credit_core eval "MiwayCreditCore.Release.create_platform_administrator"
```

The password must meet the same policy as any other account (12+
characters, upper/lower/digit) — a weak password surfaces as a normal
error, not a crash.

## 6. Start

```
_build/prod/rel/miway_credit_core/bin/miway_credit_core start
```

or as a background daemon (`... daemon`), or under a process
supervisor with an `ExecStart=` line pointing at the same `start`
command — a full systemd unit is an operational choice for whoever
runs the pilot's infrastructure, not prescribed here.

## 7. Smoke test

```
curl -i https://<PHX_HOST>/up
curl -i https://<PHX_HOST>/ready
```

`/up` — expect `200` and `{"status":"ok"}`. Confirms the BEAM process
is up and Phoenix is routing; deliberately no database dependency (see
the doc comment on `MiwayCreditCoreWeb.HealthController.show/2`).

`/ready` — expect `200` and `{"status":"ready"}`; `503` means Postgres is
unreachable from this instance (wrong process, not a crash — a load
balancer should route around it rather than treat it as fully down).
Point your orchestrator's readiness probe (not its liveness probe) at
this one.

## 8. ClamAV — a hard prerequisite for KYC uploads, not optional

`MiwayCreditCore.Customers.MalwareScanner.Local` shells out to the
`clamscan` binary before any KYC upload is encrypted and stored. It
fails closed (`lib/miway_credit_core/customers/malware_scanner/local.ex`):
missing binary, crash, or unrecognized exit code all reject the
upload rather than store it unscanned. **This means every KYC upload
in production will be rejected until ClamAV is installed and
working** — there is no "scanning disabled" mode, by design.

- **Install** (Debian/Ubuntu-family hosts): `apt-get install clamav clamav-daemon`,
  then `freshclam` once manually to pull the initial virus-definition
  database before first use.
- **Signature updates**: `clamav-freshclam`'s own systemd timer/daemon
  handles this on most distros — confirm it's enabled
  (`systemctl status clamav-freshclam`) rather than assuming it. Stale
  signatures don't make scanning fail (still fails closed on a crash),
  but they do reduce detection quality silently.
- **Health verification**: `clamscan --version` should print a version
  and exit 0; `echo test | clamscan -` should exit 0 (clean). Run both
  after install and after any host migration, before the first real
  KYC upload.
- **Test upload**: upload one real KYC document through the app after
  deploy and confirm it succeeds — the fail-closed design means a
  broken ClamAV install shows up immediately as every upload being
  rejected, not as a silent gap.
- **Scanner-outage procedure**: if `clamscan` breaks in production
  (crashed, uninstalled by a host update, disk full so freshclam can't
  write), KYC uploads fail hard and visibly — that's the intended
  behavior, not a bug to route around. Fix ClamAV first; do not
  reconfigure the app to skip scanning as a workaround.

**Not live-verified in this environment** — ClamAV isn't installed in
this sandbox, so only the fail-closed-when-absent path has actually
been exercised here (confirmed: uploads are correctly rejected with no
orphaned file on disk). The real detection path (`clamscan` finding an
actual virus) needs to be verified against a real ClamAV install
before a pilot, e.g. with the EICAR test file.

## 9. KYC document storage — needs a real operational decision before a pilot

`MiwayCreditCore.Customers.DocumentStorage` writes encrypted KYC bytes
to local disk, at a path set by the required `KYC_UPLOAD_DIR` env var
(§1) — the release **refuses to boot in production without it set**,
specifically so a persistent path can't be silently forgotten and only
discovered after the first deploy wipes uploaded documents. (The
`priv/kyc_uploads/` default only applies in dev/test, where it doesn't
matter.)

- **Use a persistent path outside the release directory.** A release
  deploy typically replaces the whole release directory; anything
  stored inside it is lost on the next deploy. Point `KYC_UPLOAD_DIR`
  at a separate, persistent volume
  (e.g. `/var/lib/miway_credit_core/kyc_uploads`) that survives
  releases, and confirm the OS user the release runs as can write to
  it before first boot.
- **Back up the KYC files, not just the database.** The database only
  stores metadata (`KycDocument` rows) — the actual encrypted bytes
  live solely on that disk path. A database backup alone does not
  protect customer documents.
- **Test restoration**, not just backup — a backup that has never been
  restored is unverified. Confirm a restored file still decrypts (see
  below) and matches its `KycDocument` row.
- **Monitor storage capacity.** Uploads are capped at 10MB each
  (`KycDocument` changeset validation), but there's no automatic
  alerting on disk usage — add one at the infrastructure level.
- **`KYC_ENCRYPTION_KEY` backup and rotation.** This key (§1) decrypts
  every stored document — losing it makes every file permanently
  unreadable, independent of whether the disk itself survives. Back it
  up like a secret, separately from both the database and the KYC
  files themselves (so a single lost backup can't take out both the
  ciphertext and the key). Key **rotation** is not currently built —
  today's design assumes one long-lived key; rotating it would require
  a migration that re-encrypts every stored document with a new key,
  not yet implemented.
- **Multi-server deployment.** Local disk storage does not work across
  multiple app servers behind a load balancer — each instance would
  only see its own files. A single-instance deployment is the only
  configuration this storage layer currently supports correctly; a
  shared network filesystem or moving `DocumentStorage` to
  object storage (S3-compatible) would be required before running more
  than one app instance. `DocumentStorage`'s own moduledoc already
  scopes it this way ("swap this module's internals for S3 later
  without touching the context or controller").

## 9a. TOTP (MFA) secret encryption key — `MFA_ENCRYPTION_KEY`

`MiwayCreditCore.Accounts.TotpCrypto` encrypts every user's TOTP
secret at rest (AES-256-GCM, same mechanism and code shape as
`DocumentStorage`'s KYC encryption in §9, but its own key —
`users.totp_secret` holds a Base64-encoded `nonce <> tag <>
ciphertext` blob, not the plaintext-Base64 secret older versions of
this app stored). This closes a real gap: a database copy alone used
to be enough to decode every user's MFA seed and generate valid codes,
defeating the point of two-factor authentication.

- **Never reuse `KYC_ENCRYPTION_KEY` for this.** They protect
  different things (KYC documents vs. MFA seeds) and a shared key
  means compromising one exposes both. `config/runtime.exs` requires
  both, as two independently-generated values.
- **Custody, backup, and recovery follow the exact same model as
  `KYC_ENCRYPTION_KEY` in §10's "Encryption key recovery" subsection**
  — a real secrets vault, access restricted to people distinct from
  whoever controls the backup destination, never written to the same
  destination as the database/KYC backups, and never included in the
  automated backup pipeline. Losing this key doesn't lose customer
  money or documents, but it does lock every enrolled user out of MFA
  login until they re-enroll — treat it with the same care.
- **Key-version metadata is built in, for a future rotation.**
  `users.totp_secret_version` records which format/key generation
  encrypted a given row (`0` = legacy pre-encryption plaintext-Base64,
  `1` = the current `MFA_ENCRYPTION_KEY`). A future key rotation would
  introduce version `2`, re-encrypt existing rows under the new key,
  and bump their version — the version column already exists so that
  migration doesn't need a schema change when it happens. Rotation
  itself (re-encrypting every row under a new key) is not yet built,
  matching where `KYC_ENCRYPTION_KEY` rotation stands today.
- **Existing (pre-encryption) users were migrated automatically, not
  forced to re-enroll.** `mix miway_credit_core.encrypt_existing_totp_secrets`
  re-encrypts every `totp_secret_version: 0` row in place —
  the underlying secret never changes, only how it's stored, so no
  user's authenticator app needs a new QR scan because of this change.
  Safe to re-run; it's a no-op for any row already on the current
  format. Run this once, after `MFA_ENCRYPTION_KEY` is configured and
  the app is deployed with this change.
- **Two distinct verification checks**, same two-cadence model as
  `KYC_ENCRYPTION_KEY`: `mix miway_credit_core.verify_mfa_key`
  (decrypts a sample of real users' encrypted secrets with the
  *running app's* currently loaded key — cheap, automatable, safe in
  prod, never prints the key or a decrypted secret) vs. a separate
  human quarterly exercise of retrieving the *vaulted* copy of the key
  and confirming it decrypts a real record — the only genuine
  disaster-recovery test of the backed-up key itself.

## 10. Backups and recovery

Built: an automated daily backup pipeline (`MiwayCreditCore.Backup`,
`BackupScheduler`), a verified restore drill against scratch
resources, and monitoring integration (§11) — not a checklist anymore,
a real system, exercised live against the actual dev database as part
of building it (evidence at the end of this section). What's still a
genuine deployment decision, not built here, is called out explicitly
in its own subsection below.

### What runs, and what it produces

`BackupScheduler` runs `Backup.run/1` daily (first tick 1 minute after
boot, then every 24h — `config :miway_credit_core, MiwayCreditCore.BackupScheduler, interval_ms: ...`
to change it). Guarded by a local lock file (`Backup.Lock`, atomic
`O_EXCL`, self-heals after 6h in case a prior run crashed mid-way) so
a scheduled tick and a manual `mix miway_credit_core.backup` can never
clobber each other.

Each run produces one `backup_id` (a sortable UTC timestamp,
`YYYYMMDDTHHMMSSZ`) containing four files, written through the
configured `Backup.Destination` adapter:

- `db.dump` — `pg_dump --format=custom` (supports selective restore,
  built-in compression).
- `kyc.tar.gz` — a tar of the entire `KYC_UPLOAD_DIR`. These files are
  already AES-256-GCM-encrypted at rest by the app itself before this
  pipeline ever touches them (§9) — archiving them doesn't add a
  second layer, it preserves the existing one byte-for-byte.
- `manifest.json` — row counts for a curated set of key tables, a
  canary record (the most recently inserted KYC document, so a drill
  can assert a *specific* record survived, not just a count), a
  per-file sha256 for every KYC file, and an optional non-reversible
  sha256 **fingerprint** of the KYC encryption key (never the key
  itself — same trust model as a password hash; lets you match a
  backup to the key generation it was encrypted under without ever
  exposing that key).
- `SHA256SUMS` — real `sha256sum` output format, covering all three
  files above. Independently re-verifiable with no dependency on this
  app: `sha256sum -c SHA256SUMS`.

Retention keeps the newest 14 backups by default
(`config :miway_credit_core, :backup_retention_count`), pruned right
after each successful run.

**Required config**: `BACKUP_ROOT_DIR` (§1) — the `Local` destination
adapter's root. A real off-site destination (S3, rsync to a second
host, ...) is a deploy-time addition (see below); `Local` is the only
adapter built, same treatment SMTP/ClamAV got before it.

### Restoring for real

```
mix miway_credit_core.backup            # or wait for the daily tick
mix miway_credit_core.restore_drill      # defaults to the latest backup
mix miway_credit_core.restore_drill --backup-id=20260731T055733Z
```

In a real deployed release (no Mix available), the equivalents are:

```
bin/miway_credit_core eval "MiwayCreditCore.Release.run_backup"
bin/miway_credit_core eval "MiwayCreditCore.Release.run_restore_drill"
```

The drill restores into a **scratch database** (`<real database>_restore_drill`
— a fixed suffix, not a parameter; there is no way to point it at an
arbitrary or the real database) and a **scratch KYC directory** (under
the OS tmp dir, categorically separate from the real persistent
volume), verifies row counts + the canary record against the
manifest, and verifies every KYC file's checksum against the
manifest — never against a live query of the real database, and
**never by decrypting anything** (checksum comparison is a stronger
byte-fidelity guarantee than decrypt-and-inspect, and keeping
`KYC_ENCRYPTION_KEY` out of this automated path is itself part of
keeping it genuinely separate — see below). On success, the scratch
database is dropped and the scratch directory removed; on any failure
(including an unexpected crash, not just an expected error) both are
left in place for inspection, and the printed report always names
them.

**An actual restoration in an incident**, in order: (1) stop the app
(or at least writes to it), (2) `pg_restore` the chosen `db.dump` into
the real database — `--clean` if restoring over existing data, a
fresh `CREATE DATABASE` if starting clean, (3) extract `kyc.tar.gz`
into the real `KYC_UPLOAD_DIR`, (4) confirm `KYC_ENCRYPTION_KEY` in
the environment matches the backup's manifest fingerprint before
starting the app (a mismatched key means every KYC document decrypts
to garbage — check *before* traffic resumes, not after), (5) start the
app, (6) smoke-test (§7) before considering the incident resolved.

**Recovery objectives (proposed, needs a real business decision before
a pilot)**: RPO ~24h (matches the daily backup cadence — a shorter RPO
needs Postgres point-in-time recovery from your hosting provider, not
just this pipeline). RTO: restoring a database this size took well
under a minute in every live test during development; a real
incident's actual RTO also depends on provisioning a replacement host,
which this document can't estimate for you.

### Encryption key recovery — a separate, human-gated procedure

`KYC_ENCRYPTION_KEY` (and `SECRET_KEY_BASE`) are **never** written to
the same destination as the Postgres/KYC backups above, and there is
no automated backup of them in this codebase — deliberately. Store
them in a real secrets vault (a shared password-manager vault, a cloud
secrets manager, or at minimum a sealed physical copy in a safe for an
early pilot), with access restricted to people who are **not** the
same people who control the backup destination — a single compromise
must never be able to take out both the ciphertext and the key that
opens it.

Two distinct checks, on different cadences, testing different things:

- `mix miway_credit_core.verify_kyc_key` — decrypts a sample of real
  stored documents using the key the *running app* currently has
  loaded. Cheap, automatable, safe to run in prod. Confirms the app's
  own configuration is internally consistent — it does **not** prove
  the vaulted copy is recoverable.
- A separate, human, quarterly exercise: actually retrieve the
  *vaulted* copy of the key and confirm that specific copy decrypts a
  real file. This is the only genuine disaster-recovery test of the
  backed-up key — skipping it and only ever running the tool above
  would mean discovering a bad vault entry during a real incident,
  not before one.

Record the key's sha256 fingerprint (the same value a backup manifest
optionally records) next to the vault entry — it lets you confirm a
recovered key candidate matches what a given backup expects without
ever decrypting anything to check.

### Still needs real infrastructure or a deployment decision — not built, not faked

- **A real off-site destination.** `Backup.Destination.Local` is the
  only adapter built; backups today live on the same host as the
  database they're backing up. A real deployment needs an S3 (or
  equivalent) or second-host adapter — the `Destination` behaviour
  is the seam to build it against, same pattern `PasswordResetNotifier`/
  `MalwareScanner` already established for SMTP/ClamAV.
- **Encryption of the Postgres dump itself at rest.** `db.dump`
  contains full plaintext customer/financial data (unlike the KYC
  archive, which is already ciphertext) — if the backup destination
  itself isn't encrypted at rest (an encrypted disk/bucket), that's a
  real gap. Worth solving at the destination layer (an encrypting S3
  adapter, or the storage provider's own at-rest encryption) rather
  than adding a second application-level encryption step here.
- **Alerting.** `BackupScheduler` failures are recorded
  (`Monitoring.record_backup_failure/1`, visible on
  `/admin/system-health` — see §11) but nothing pages anyone yet;
  wiring that up is the same deployment-specific decision §11 already
  defers for its own findings.
- **A managed-Postgres provider's own backup/PITR offering**, if you
  have one — this pipeline doesn't replace point-in-time recovery from
  your hosting provider, it's a portable, provider-independent
  baseline underneath whatever else you have.
- **A committed schedule of restore drills.** The mechanism is built
  and proven; running it periodically (monthly, quarterly — pick a
  real cadence) and recording results is an operational habit, not
  code.

### Evidence — an actual live drill (2026-07-31, against the real dev database)

Sanitized output of `mix miway_credit_core.restore_drill`, run for
real during development, not a hypothetical:

```json
{
  "overall_status": "ok",
  "backup_id_restored": "20260731T055733Z",
  "drill_id": "20260731T055733Z_35",
  "ran_at": "2026-07-31T05:57:37.149262Z",
  "kyc_restore": {
    "status": "ok",
    "files_checked": 3,
    "files_matched": 3,
    "files_mismatched": 0
  },
  "postgres_restore": {
    "status": "ok",
    "canary_found?": true,
    "table_row_counts": {
      "customers": { "matches": true, "actual": 17, "expected": 17 },
      "kyc_documents": { "matches": true, "actual": 3, "expected": 3 },
      "loan_accounts": { "matches": true, "actual": 11, "expected": 11 },
      "loan_applications": { "matches": true, "actual": 22, "expected": 22 },
      "payment_transactions": { "matches": true, "actual": 9, "expected": 9 },
      "staff_members": { "matches": true, "actual": 8, "expected": 8 },
      "users": { "matches": true, "actual": 10, "expected": 10 }
    }
  }
}
```

Confirmed via `psql -l` and `find /tmp` immediately afterward that no
scratch database or directory was left behind, and that the real dev
database and KYC directory were untouched throughout.

## 11. Monitoring

This section deliberately separates three different things, since
conflating them is how a real deployment ends up with a green
dashboard nobody actually watches:

1. **Application health visibility** — the app can tell you whether
   it, and the things it depends on internally, look healthy. Fully
   built (below).
2. **External alerting** — something watching that visibility and
   waking a human up. Not built here — this app exposes data, it does
   not page anyone. See "Still needs real infrastructure" below.
3. **Host/infrastructure monitoring** — the Postgres server, the
   container/VM, the network — things genuinely outside this
   application's process boundary. Also not built here, and can't be:
   an app can't reliably observe the disk of a different machine.

### Application health visibility (built)

A self-contained `MiwayCreditCore.Monitoring` layer (no new
dependency — hand-rolled `:telemetry.attach/4` against events
Phoenix/Ecto already emit) plus `/admin/system-health`, a
platform-administrator-only page surfacing all of it in one place
instead of a log-grep exercise. Every value visible is diagnostic
only (timestamps, counts, byte counts, ms) — no exception text,
stack traces, credentials, SQL, customer data, or file paths are ever
rendered.

- Point an uptime monitor at `/up`, and an orchestrator/load-balancer
  readiness probe at `/ready`.
- Error/exception capture — `Monitoring.ErrorReporter` (a swappable
  behaviour, same shape as `PasswordResetNotifier`) attached to
  Phoenix's `[:phoenix, :error_rendered]` telemetry event. The
  `Default` adapter logs a structured, greppable `[error_reporter]`
  line — the real, shippable default in every environment, not a
  placeholder. Configure `config :miway_credit_core, :error_reporter`
  to point at a real Sentry/AppSignal adapter later; none is built
  here, since there's no such account/dependency to build against.
- Database connection-pool visibility — `Monitoring.pool_stats/0`
  tracks lifetime sample count/last queue time (ms) plus a **windowed**
  max (resets every 5 minutes alongside the scanner-failure prune —
  see `Store.max_queue_time_window_seconds/0` — so a resolved spike
  doesn't sit there looking like an ongoing problem forever) via
  Ecto's own `[:miway_credit_core, :repo, :query]` telemetry.
  `Monitoring.pool_healthy?/0` flags the current window's max at or
  above 200ms (an operator-facing threshold shown as an OK/Warning
  badge, not itself an alert). `POOL_SIZE` (§1) is still fixed; a
  persistently rising max is the earliest sign of exhaustion, before
  `/ready` itself starts failing.
- `KycRetentionScheduler`/`ArrearsScheduler` heartbeats —
  `Monitoring.record_tick/1`/`stale?/2`, visible as an OK/Stale badge
  per scheduler. A scheduler is flagged stale once its last tick is
  older than 2x its own default tick interval (ArrearsScheduler: 2h;
  KycRetentionScheduler: 48h — a hardcoded diagnostics constant in
  `SystemHealthController`, not a config surface).
- `MalwareScanner` failure counter and last-failure time — every
  `{:error, reason}` result from any adapter increments
  `Monitoring.recent_scanner_failure_count/1` and updates
  `Monitoring.last_scanner_failure_at/0`, both shown together — a
  count alone can't distinguish "failed once an hour ago" from "still
  failing right now." A rising count is the earliest signal of a
  broken ClamAV install (§8).
- KYC upload directory disk space — `Monitoring.disk_free_bytes/1`.
- SMTP delivery failures — already logged (`Logger.error`, in
  `Notifications.deliver_password_reset_email/3`) but deliberately
  **not** given a `Monitoring` counter of its own: email delivery is a
  low-volume, non-critical-path operation (unlike KYC uploads or
  scheduler ticks), and its existing log line is left to the same
  log-based/external monitoring this section's "Still needs real
  infrastructure" items already depend on, rather than adding a
  disproportionate amount of new instrumentation for it.
- **A monitoring failure can never crash or block a lending
  operation.** `Monitoring.record_tick/1`, `record_scanner_failure/1`,
  and `record_query_sample/1` — the only write functions anything
  outside `Monitoring` itself calls — each catch and log their own
  failures internally rather than let them propagate; this matters
  concretely for `record_scanner_failure/1`, which is called directly
  from `MalwareScanner.scan/1`, sitting in the real KYC upload path.
  Both telemetry handlers (`handle_repo_query/4`,
  `handle_error_rendered/4`) are wrapped the same way, since
  `:telemetry` permanently (and silently) detaches a handler forever
  the instant it raises once.
- `/admin/system-health` is tested end-to-end: a platform administrator
  gets a real 200 with real data; an organisation administrator and a
  loan officer both get a real 403 (a genuine server-side deny, not a
  hidden UI element — confirmed by hitting the route directly); an
  unauthenticated request is redirected to `/login`.

**Known limitations of `Monitoring.Store` (the ETS table backing all
of this), worth restating precisely:**

- It survives a *writer* process crashing and restarting (a scheduler,
  a telemetry handler) because `Store` is supervised separately from
  them. It does **not** survive `Store`'s own process crashing (ETS
  tables are destroyed when their owner terminates; no `:heir` is
  configured — not worth the complexity for diagnostics-only data), an
  application/VM/container/host restart, or a redeploy. All of it is a
  **runtime indicator, not a permanent record** — `AuditLogs`, backed
  by Postgres, is the durable trail for anything that needs one.
- The table is `:public`, not `:protected` — a deliberate choice, not
  an oversight: five independent processes write to it directly
  (two schedulers, `MalwareScanner`, two telemetry handlers), mirroring
  this codebase's own `PlugAttack.Storage.Ets` precedent for the same
  multi-writer reason. Every write in the codebase goes through
  `Monitoring`'s public functions — nothing reaches into the table
  directly — so treat that module boundary as the actual guarantee,
  not the ETS access mode.
- All of it is **local to one running instance**. In a multi-server
  deployment, each instance has its own independent counters/heartbeats
  — there is no cross-instance aggregation. This app has no
  horizontal-scaling story today (single `POOL_SIZE`, single set of
  schedulers assumed), so this is a latent limitation to revisit if
  that ever changes, not an active gap.
- `/admin/system-health` provides visibility. **It does not alert
  anyone by itself** — nothing pages an operator just because a badge
  turns red. Wiring it (or the structured log lines it's built on)
  into something that does is exactly the next section.

### Still needs real infrastructure — not built, not faked

- Disk-space monitoring for the Postgres host itself — a separate
  machine in most real deployments, and not reliably observable from
  inside this application's process even when co-located; monitor it
  directly at the host level.
- Alert on backup failures (§10) once a real scheduled backup process
  exists to monitor (see the recommended next step below).
- Audit-log monitoring — `AuditLogs` (Step 16) records
  `login_failure`/`2fa_blocked_lockout`/etc., but nothing currently
  watches this table for a spike indicating an attack in progress.
  This needs defined rules and thresholds calibrated against real
  traffic, not a number picked in the abstract — add once that traffic
  exists.
- An external uptime monitor actually pointed at `/up`, and an
  orchestrator/load-balancer actually configured to use `/ready` as
  its readiness probe — both endpoints exist and work today, but
  nothing is watching them until a real deployment target does.
- Wiring any of the above — plus `/admin/system-health`'s data and
  `ErrorReporter`'s structured log lines — into an actual
  paging/alerting product (PagerDuty, Opsgenie, a Slack webhook, ...)
  so a human actually gets woken up. This app exposes the data;
  routing it to a person is a deployment-specific decision this
  sandbox can't make.

## 12. Password-reset email delivery (SMTP)

Password-reset links are delivered through `MiwayCreditCore.Notifications`
(a Swoosh mailer) via any SMTP-speaking provider — SendGrid, Mailgun,
Postmark, AWS SES, Zoho, a private mail server, etc. There is no
vendor-specific SDK, so switching providers later is just changing
env vars, not code.

**Deliberately optional at boot**, unlike `DATABASE_URL`/
`SECRET_KEY_BASE` (§1): if `SMTP_HOST` is unset, the release still
boots and runs fine — reset requests are accepted, but delivery fails
closed server-side (`Accounts.PasswordResetNotifier.Unconfigured`,
logged, never surfaced to the requester) and the reset-request page
shows "contact an administrator" instead of "check your email"
(`PasswordResetNotifier.configured?/0`). This lets a pilot start
before SMTP is arranged, then turn real delivery on later by setting
env vars and restarting — no code change, no redeploy.

**Setup:**

1. Get SMTP credentials from your chosen provider (host, port,
   username, password) and a verified sender address/domain — most
   providers reject mail from an unverified `From:` address outright.
2. Set `SMTP_HOST`, `SMTP_USERNAME`, `SMTP_PASSWORD`, `MAIL_FROM_ADDRESS`
   (required together — see §1), plus optionally `SMTP_PORT` (default
   `587`) and `MAIL_FROM_NAME`.
3. Restart the release. `config/runtime.exs` picks these up and
   switches `:password_reset_notifier` from `Unconfigured` to `Email`
   automatically — nothing else to configure.
4. TLS is STARTTLS on port 587 by default, with full certificate
   verification (`verify: :verify_peer` plus hostname/SNI matching
   against `SMTP_HOST`, unlike the Postgres SSL follow-up noted in
   §2 — this connection verifies the hostname too, not just the CA
   chain). A provider requiring implicit TLS (typically port 465)
   needs `ssl: true` added to the `Notifications.Mailer` config in
   `config/runtime.exs` instead of `tls: :always`.

**Delivery testing** (do this before relying on it for a real pilot):

1. Confirm boot picked up the config:
   `bin/miway_credit_core eval "MiwayCreditCore.Accounts.PasswordResetNotifier.configured?()"`
   should return `true`.
2. Trigger a real reset request against a real inbox you control
   (`POST /password-reset` with that email, or through the UI) and
   confirm the email actually arrives — including checking spam/junk,
   since a fresh sending domain with no reputation history often lands
   there initially.
3. Confirm the link in the received email works end-to-end (opens the
   set-new-password form, the new password logs in).
4. If nothing arrives, check the application log first —
   `Notifications.deliver_password_reset_email/2` logs the provider's
   exact rejection reason (auth failure, unverified sender, rate limit,
   etc.) server-side; the UI never shows this detail, by design.

**Partially live-verified in this environment**: the not-configured
(fail-closed) and provider-failure (logged, not leaked) paths are
covered by the test suite; the real SMTP wire protocol itself
(`Swoosh.Adapters.SMTP`/`gen_smtp` — connect, `MAIL FROM`/`RCPT TO`/
`DATA`) was confirmed live against a local debug SMTP server, correct
multipart text+HTML message received byte-for-byte. What could **not**
be verified here — no real provider account or public sending domain
exists in this sandbox — is an actual provider round trip: STARTTLS
against a real cert, auth against real credentials, and inbox
delivery/reputation (§2's hostname-verification note applies here
too — confirm TLS actually negotiates against your real provider, not
just that the code compiles). Confirm all of that against a real
provider before a pilot, the same way ClamAV's real detection path
(§8) does.
