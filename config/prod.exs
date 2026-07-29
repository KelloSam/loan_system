import Config

# Static production config — runtime secrets and DB URL are in config/runtime.exs

config :miway_credit_core, MiwayCreditCore.Repo,
  # pool_size and DATABASE_URL are set via env vars in runtime.exs
  #
  # ssl_opts is required, not optional — bare ssl: true alone fails
  # every connection, since Postgrex defaults verify: :verify_peer once
  # SSL is on but supplies no CA store to verify against. cacerts_get/0
  # loads the OTP-bundled trusted CA store, which validates any
  # publicly-trusted managed Postgres cert (RDS, DigitalOcean, Render,
  # Supabase, etc). A private/self-signed-CA deployment instead needs
  # cacertfile: "/path/to/ca.pem" in place of cacerts: below — see
  # docs/MIWAY_CREDITCORE_DEPLOYMENT_RUNBOOK.md.
  ssl: true,
  ssl_opts: [verify: :verify_peer, cacerts: :public_key.cacerts_get()]

config :miway_credit_core, MiwayCreditCoreWeb.Endpoint,
  # Force HTTPS in production
  force_ssl: [rewrite_on: [:x_forwarded_proto]],
  url: [scheme: "https", port: 443],
  cache_static_manifest: "priv/static/cache_manifest.json"

# Do not log debug messages in production
config :logger, level: :info

