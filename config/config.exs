import Config

# Configure Ecto repos
config :miway_credit_core, ecto_repos: [MiwayCreditCore.Repo]

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

