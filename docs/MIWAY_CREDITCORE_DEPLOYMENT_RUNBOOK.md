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
| `KYC_UPLOAD_DIR` | yes | absolute path to a **persistent volume outside the release directory** — see §9. The release refuses to boot without it, specifically so this can't be silently forgotten and only discovered after the first deploy wipes uploaded documents. |

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

## 10. Backups and recovery

Not yet operationally defined — this section is a checklist to work
through before a pilot, not a description of something already running.

- **PostgreSQL**: define a real backup schedule (managed Postgres
  providers typically offer automated daily backups plus point-in-time
  recovery — confirm what your chosen provider gives you by default
  vs. what you must configure).
- **KYC file backup**: separate from the database backup (§9) — the
  encrypted files on disk need their own backup schedule.
- **Encryption key backup**: `KYC_ENCRYPTION_KEY` and `SECRET_KEY_BASE`
  both need a durable backup independent of the database and app
  servers — losing either is unrecoverable (KYC documents; all active
  sessions, respectively).
- **Off-site copies**: backups stored only on the same host/provider as
  production don't protect against a provider-level incident.
- **Restore procedure**: write down the actual steps (which backup,
  which order — database before or after KYC files, how the app is
  taken down/up around a restore) rather than improvising during a
  real incident.
- **Recovery objectives**: agree on an RPO (how much data loss is
  acceptable — since last backup?) and RTO (how long restoration is
  allowed to take) before a pilot, not after an incident.
- **Restore drills**: schedule periodic real restores to a scratch
  environment. A backup is not proven until it has been restored
  successfully — an untested backup is a hope, not a guarantee.

## 11. Monitoring

Beyond `/up`/`/ready` (§7), not yet built — a checklist for pilot
readiness:

- Point an uptime monitor at `/up`, and an orchestrator/load-balancer
  readiness probe at `/ready`.
- Error/exception monitoring (e.g. Sentry, AppSignal, or Phoenix's own
  `Logger`-based alerting) — nothing currently forwards unhandled
  exceptions anywhere but the log.
- Database connection-pool monitoring — `POOL_SIZE` (§1) is fixed;
  watch for exhaustion under real load, which would surface as slow
  requests before `/ready` itself starts failing.
- Disk-space monitoring for both the Postgres host and the KYC upload
  path (§9) — both fail destructively when full (writes fail; ClamAV's
  `freshclam` can't update signatures).
- Alert on `KycRetentionScheduler`/`ArrearsScheduler` failures — both
  are GenServers with no external alerting today; a silently-crashed
  scheduler (e.g. arrears stop accruing penalties, KYC purge stops
  running) would currently only be visible in application logs.
- Alert on repeated `MalwareScanner.Local` `{:error, :scanner_unavailable}`
  results — this is the earliest signal of a broken ClamAV install
  (§8), and currently only visible as a spike of rejected uploads.
- Alert on backup failures (§10) once a backup job exists to monitor.
- Audit-log monitoring — `AuditLogs` (Step 16) records
  `login_failure`/`2fa_blocked_lockout`/etc., but nothing currently
  watches this table for a spike indicating an attack in progress; add
  alerting once real traffic exists to set a meaningful threshold
  against.
