import Config

# Static production config — runtime secrets and DB URL are in config/runtime.exs

config :miway_credit_core, MiwayCreditCore.Repo,
  # pool_size and DATABASE_URL are set via env vars in runtime.exs
  ssl: true

config :miway_credit_core, MiwayCreditCoreWeb.Endpoint,
  # Force HTTPS in production
  force_ssl: [rewrite_on: [:x_forwarded_proto]],
  url: [scheme: "https", port: 443],
  cache_static_manifest: "priv/static/cache_manifest.json"

# Do not log debug messages in production
config :logger, level: :info

