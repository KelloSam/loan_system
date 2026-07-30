import Config

# Delivers to the calling test process instead of sending anything real.
config :miway_credit_core,
       :password_reset_notifier,
       MiwayCreditCore.Accounts.PasswordResetNotifier.Test

# Captured in-memory (Swoosh.TestAssertions) rather than sent — used by
# tests that exercise the Notifications/Email adapter path directly,
# rather than going through the Test notifier above.
config :miway_credit_core, MiwayCreditCore.Notifications.Mailer, adapter: Swoosh.Adapters.Test

config :miway_credit_core, :mail_from_address, "no-reply@miway.local"
config :miway_credit_core, :mail_from_name, "Miway CreditCore"

config :miway_credit_core, :malware_scanner, MiwayCreditCore.Customers.MalwareScanner.Test

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
config :miway_credit_core, MiwayCreditCore.KycRetentionScheduler, enabled: false

# Keep KYC document uploads out of priv/ during tests — a throwaway
# tmp dir instead, so the test suite never leaves files behind in the repo.
config :miway_credit_core, :kyc_upload_dir, Path.join(System.tmp_dir!(), "miway_kyc_test_uploads")

# Fixed, checked-in key — test data is never real customer data.
config :miway_credit_core, :kyc_encryption_key, "u6lPIl6jo+XwIdtkkHejcYC1qoAWI3icozx+JyKY4Jo="

