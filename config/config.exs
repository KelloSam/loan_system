import Config

# Configure Ecto repos
config :miway_credit_core, ecto_repos: [MiwayCreditCore.Repo]

# Every configured mail adapter (Local/Test/SMTP) delivers directly —
# none of them go over Swoosh's HTTP API client, so disable it rather
# than carry an unused Finch pool.
config :swoosh, :api_client, false

# Render a real error page/JSON body for exceptions instead of Phoenix's
# ancient fallback (which looks for a nonexistent MiwayCreditCoreWeb.ErrorView
# and raises ArgumentError trying to render one) — this mattered concretely
# once Step 5 needed a clean 404 for an out-of-scope record, not a crash.
config :miway_credit_core, MiwayCreditCoreWeb.Endpoint,
  render_errors: [
    formats: [html: MiwayCreditCoreWeb.ErrorHTML, json: MiwayCreditCoreWeb.ErrorJSON],
    layout: false
  ]

# Configure timezone database for Timex
config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

# Configure Decimal precision for money operations
config :decimal, :precision, 28

# How long a "removed" KYC document's on-disk bytes are kept before
# KycRetentionScheduler purges them — 2555 days (~7 years) is a common
# AML/KYC record-retention baseline in a number of jurisdictions, but
# this is NOT a legal determination. This app is for a Zambian lending
# operation — confirm the real applicable regulation (e.g. Bank of
# Zambia / the relevant financial-sector regulator's KYC/AML retention
# rules) before relying on this default in a real production
# deployment. A developer should not be the one deciding this number
# for a live compliance control.
config :miway_credit_core, :kyc_retention_days, 2555

# Default exception-reporting adapter — see MiwayCreditCore.Monitoring.ErrorReporter.
# Structured logging is a legitimate terminal action in every environment
# (unlike e.g. password-reset delivery), so this needs no per-env override
# and no runtime.exs gating.
config :miway_credit_core, :error_reporter, MiwayCreditCore.Monitoring.ErrorReporter.Default

# Use Jason for JSON parsing
config :phoenix, :json_library, Jason

# Configure esbuild to bundle assets/js/app.js
config :esbuild,
  version: "0.17.11",
  default: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind to compile assets/css/app.css
config :tailwind,
  version: "3.4.3",
  default: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Import environment specific config
import_config "#{config_env()}.exs"
