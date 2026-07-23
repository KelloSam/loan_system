import Config

# Configure loan system database for test environment
config :miway_credit_core, MiwayCreditCore.Repo,
  username: "think",
  password: "password1",
  hostname: "localhost",
  port: 5433,
  database: "miway_credit_core_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

# Phoenix test configuration for later use
config :miway_credit_core, MiwayCreditCoreWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4001],
  secret_key_base: "B9XwKx0e0NV3hv6fojAlQ7tg3E59TQQu2q9h8xFPM9fCfxKu8F9P/eAgO83MG0qM",
  server: false

# The background arrears scheduler queries the DB from its own process,
# outside any test's checked-out sandbox connection — disabled here;
# MiwayCreditCore.Loans.mark_overdue_payments/0 is unit-tested directly.
config :miway_credit_core, MiwayCreditCore.ArrearsScheduler, enabled: false

