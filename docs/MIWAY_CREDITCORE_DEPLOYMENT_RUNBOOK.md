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

Beyond `/up`/`/ready` (§7): a self-contained `MiwayCreditCore.Monitoring`
layer (no new dependency — hand-rolled `:telemetry.attach/4` against
events Phoenix/Ecto already emit) plus `/admin/system-health`, a
platform-administrator-only page surfacing all of it in one place
instead of a log-grep exercise.

**Built:**

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
  tracks sample count/last/max queue time via Ecto's own
  `[:miway_credit_core, :repo, :query]` telemetry, visible on
  `/admin/system-health`. `POOL_SIZE` (§1) is still fixed; a
  persistently rising max is the earliest sign of exhaustion, before
  `/ready` itself starts failing.
- `KycRetentionScheduler`/`ArrearsScheduler` heartbeats —
  `Monitoring.record_tick/1`/`stale?/2`, visible on
  `/admin/system-health` as an OK/Stale badge per scheduler.
- `MalwareScanner` failure counter — every `{:error, reason}` result
  from any adapter increments `Monitoring.recent_scanner_failure_count/1`,
  visible on `/admin/system-health` — a rising count is the earliest
  signal of a broken ClamAV install (§8).
- KYC upload directory disk space — `Monitoring.disk_free_bytes/1`,
  visible on `/admin/system-health`.

**Still needs real infrastructure — not built, not faked:**

- Disk-space monitoring for the Postgres host itself — a separate
  machine in most real deployments, not observable from this app;
  monitor it directly at the host level.
- Alert on backup failures (§10) once a backup job exists to monitor.
- Audit-log monitoring — `AuditLogs` (Step 16) records
  `login_failure`/`2fa_blocked_lockout`/etc., but nothing currently
  watches this table for a spike indicating an attack in progress; add
  alerting once real traffic exists to set a meaningful threshold
  against.
- Wiring any of the above into an actual paging/alerting product
  (PagerDuty, Opsgenie, a Slack webhook, ...) — this app exposes the
  data; routing it to a human is a deployment-specific decision.

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
