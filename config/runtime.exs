import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere.

if System.get_env("PHX_SERVER") do
  config :miway_credit_core, MiwayCreditCoreWeb.Endpoint, server: true
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one with: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || raise "environment variable PHX_HOST is missing."

  kyc_encryption_key =
    System.get_env("KYC_ENCRYPTION_KEY") ||
      raise """
      environment variable KYC_ENCRYPTION_KEY is missing.
      Generate one with: :crypto.strong_rand_bytes(32) |> Base.encode64()
      """

  config :miway_credit_core, :kyc_encryption_key, kyc_encryption_key

  kyc_upload_dir =
    System.get_env("KYC_UPLOAD_DIR") ||
      raise """
      environment variable KYC_UPLOAD_DIR is missing.
      Must be a persistent path outside the release directory — a
      release deploy replaces the release directory, so the default
      dev/test path (priv/kyc_uploads/ inside it) would lose every
      stored KYC document on the next deploy. See
      docs/MIWAY_CREDITCORE_DEPLOYMENT_RUNBOOK.md.
      """

  config :miway_credit_core, :kyc_upload_dir, kyc_upload_dir

  config :miway_credit_core, MiwayCreditCore.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

  config :miway_credit_core, MiwayCreditCoreWeb.Endpoint,
    url: [host: host],
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: String.to_integer(System.get_env("PORT") || "4000")],
    secret_key_base: secret_key_base

  # Password-reset email delivery. Deliberately optional, unlike
  # DATABASE_URL/SECRET_KEY_BASE above: a pilot can boot and run
  # without SMTP configured yet — reset requests just fail closed
  # server-side (see Accounts.PasswordResetNotifier.Unconfigured)
  # until SMTP_HOST is set, at which point delivery turns on with no
  # code change or redeploy. Works with any SMTP-speaking provider
  # (SendGrid, Mailgun, Postmark, SES, Zoho, etc) — see
  # docs/MIWAY_CREDITCORE_DEPLOYMENT_RUNBOOK.md for provider setup.
  if smtp_host = System.get_env("SMTP_HOST") do
    smtp_username =
      System.get_env("SMTP_USERNAME") ||
        raise "environment variable SMTP_USERNAME is missing (required once SMTP_HOST is set)."

    smtp_password =
      System.get_env("SMTP_PASSWORD") ||
        raise "environment variable SMTP_PASSWORD is missing (required once SMTP_HOST is set)."

    mail_from_address =
      System.get_env("MAIL_FROM_ADDRESS") ||
        raise "environment variable MAIL_FROM_ADDRESS is missing (required once SMTP_HOST is set)."

    config :miway_credit_core, MiwayCreditCore.Notifications.Mailer,
      adapter: Swoosh.Adapters.SMTP,
      relay: smtp_host,
      port: String.to_integer(System.get_env("SMTP_PORT") || "587"),
      username: smtp_username,
      password: smtp_password,
      tls: :always,
      tls_options: [
        verify: :verify_peer,
        cacerts: :public_key.cacerts_get(),
        server_name_indication: String.to_charlist(smtp_host),
        customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
      ],
      auth: :always,
      retries: 2,
      no_mx_lookups: true

    config :miway_credit_core, :mail_from_address, mail_from_address

    config :miway_credit_core,
           :mail_from_name,
           System.get_env("MAIL_FROM_NAME") || "Miway CreditCore"

    config :miway_credit_core,
           :password_reset_notifier,
           MiwayCreditCore.Accounts.PasswordResetNotifier.Email
  end
end
