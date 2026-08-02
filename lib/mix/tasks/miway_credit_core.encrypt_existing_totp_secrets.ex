defmodule Mix.Tasks.MiwayCreditCore.EncryptExistingTotpSecrets do
  @moduledoc """
  One-time migration: re-encrypts every user's legacy
  (`totp_secret_version: 0`) TOTP secret into the current AES-256-GCM
  format, in place. Unlike the KYC-file equivalent, this is safe to
  run more than once — `Accounts.migrate_legacy_totp_secret/1` is a
  no-op for any row already on the current format.

  Existing MFA enrollments keep working throughout: nothing about the
  underlying secret changes, only how it's stored, so no user needs to
  re-scan a QR code because of this migration.

  Run this once, right after deploying the commit that adds
  encryption-at-rest for TOTP secrets (and after `MFA_ENCRYPTION_KEY`
  is configured — see docs/MIWAY_CREDITCORE_DEPLOYMENT_RUNBOOK.md).

      mix miway_credit_core.encrypt_existing_totp_secrets
  """

  use Mix.Task
  import Ecto.Query

  alias MiwayCreditCore.Accounts
  alias MiwayCreditCore.Accounts.User
  alias MiwayCreditCore.Repo

  @shortdoc "One-time: encrypts existing legacy-format TOTP secrets in place"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    users =
      Repo.all(
        from u in User,
          where: u.totp_secret_version == 0 and not is_nil(u.totp_secret)
      )

    {ok, failed} =
      Enum.split_with(users, fn user ->
        case Accounts.migrate_legacy_totp_secret(user) do
          {:ok, _} -> true
          {:error, _} -> false
        end
      end)

    Mix.shell().info("#{length(ok)}/#{length(users)} legacy TOTP secret(s) migrated.")

    if failed != [] do
      Mix.shell().error("Failed to migrate user id(s): #{Enum.map_join(failed, ", ", & &1.id)}")
      System.halt(1)
    end
  end
end
