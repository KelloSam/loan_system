import Config

# Configure Ecto repos
config :miway_credit_core, ecto_repos: [MiwayCreditCore.Repo]

# Configure timezone database for Timex
config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

# Configure Decimal precision for money operations
config :decimal, :precision, 28

# Use Jason for JSON parsing
config :phoenix, :json_library, Jason

# Import environment specific config
import_config "#{config_env()}.exs"

