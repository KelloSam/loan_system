import Config

# Ecto logs every query at :debug by default — under the sandbox pool
# that's thousands of "QUERY OK ..." lines per `mix test` run, drowning
# out genuine failures and making the full suite impractical to read
# (flagged in external review of ba4d5ba). Real test failures (ExUnit's
# own output) and Ecto/Postgrex errors still surface — errors log well
# above :warning, so nothing that actually matters is hidden.
#
# To temporarily see full SQL debug output while diagnosing a specific
# test, override this without editing the file:
#
#     LOG_LEVEL=debug mix test test/path/to/some_test.exs
#
config :logger, level: System.get_env("LOG_LEVEL", "warning") |> String.to_existing_atom()

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
config :miway_credit_core, MiwayCreditCore.BackupScheduler, enabled: false

# Keep KYC document uploads out of priv/ during tests — a throwaway
# tmp dir instead, so the test suite never leaves files behind in the repo.
config :miway_credit_core, :kyc_upload_dir, Path.join(System.tmp_dir!(), "miway_kyc_test_uploads")

# Same reasoning for backups — a throwaway tmp dir, never priv/backups.
config :miway_credit_core, :backup_root_dir, Path.join(System.tmp_dir!(), "miway_backup_test")

# Fixed, checked-in key — test data is never real customer data.
config :miway_credit_core, :kyc_encryption_key, "u6lPIl6jo+XwIdtkkHejcYC1qoAWI3icozx+JyKY4Jo="

# Fixed, checked-in key — deliberately different from :kyc_encryption_key.
config :miway_credit_core, :mfa_encryption_key, "T8Mm6SIS8B7pR4eYAMY4IlsKZgKaf7UQPWT6J5Er66g="
