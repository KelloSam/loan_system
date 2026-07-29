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

  config :miway_credit_core, MiwayCreditCore.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

  config :miway_credit_core, MiwayCreditCoreWeb.Endpoint,
    url: [host: host],
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: String.to_integer(System.get_env("PORT") || "4000")],
    secret_key_base: secret_key_base
end

