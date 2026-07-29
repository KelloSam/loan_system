import Config

# Password-reset links are logged rather than emailed until Notifications
# (see docs/architecture/context_boundaries.md) is actually built.
config :miway_credit_core, :password_reset_notifier, MiwayCreditCore.Accounts.PasswordResetNotifier.Dev

# No ClamAV assumed installed in dev — the Local adapter would fail
# closed and block every KYC upload otherwise.
config :miway_credit_core, :malware_scanner, MiwayCreditCore.Customers.MalwareScanner.Dev

# Fixed, checked-in key for KYC document encryption at rest — safe
# because dev data is never real customer data. Never reuse this key
# in prod; config/runtime.exs requires a real KYC_ENCRYPTION_KEY there.
config :miway_credit_core, :kyc_encryption_key, "e4bafnT8b29F3Nl3cozlz0haxa9xagBbhK57Y5eafGE="

# Configure loan system database
config :miway_credit_core, MiwayCreditCore.Repo,
  username: "think",
  password: "password1",
  hostname: "localhost",
  database: "miway_credit_core_dev",
  port: 5433,
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

# Phoenix configuration for later use
config :miway_credit_core, MiwayCreditCoreWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4001],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "9f6YJKc5r4kRN8XSPqp/93qZ4ixDMPXwq5Tgq/BJQ7Sq1uHSb2QXo+pKavyZH0I6",
  pubsub_server: MiwayCreditCore.PubSub,
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:default, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:default, ~w(--watch)]}
  ]

