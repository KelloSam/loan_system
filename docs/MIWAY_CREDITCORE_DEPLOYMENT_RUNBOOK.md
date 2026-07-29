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
```

Expect `200` and `{"status":"ok"}` — the health check added in Step 17.
This confirms the BEAM process is up and Phoenix is routing; it does
not check database connectivity by design (see the doc comment on
`MiwayCreditCoreWeb.HealthController.show/2`).
