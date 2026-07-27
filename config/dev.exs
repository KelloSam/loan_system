import Config

# Password-reset links are logged rather than emailed until Notifications
# (see docs/architecture/context_boundaries.md) is actually built.
config :miway_credit_core, :password_reset_notifier, MiwayCreditCore.Accounts.PasswordResetNotifier.Dev

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

