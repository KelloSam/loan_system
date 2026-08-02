defmodule Mix.Tasks.MiwayCreditCore.VerifyMfaKey do
  @moduledoc """
  Read-only sanity check: attempts to decrypt every user's
  currently-encrypted (`totp_secret_version >= 1`) TOTP secret using
  the currently configured MFA_ENCRYPTION_KEY. Never prints the key or
  any decrypted secret — only pass/fail counts and failing user ids.
  Safe to run in prod.

  This checks the key the *running app* already has loaded — it is
  not a disaster-recovery test of a *vaulted* copy of the key. See the
  deployment runbook's MFA key custody section for that separate,
  human-gated exercise.

      mix miway_credit_core.verify_mfa_key
  """

  use Mix.Task
  import Ecto.Query

  alias MiwayCreditCore.Accounts
  alias MiwayCreditCore.Accounts.User
  alias MiwayCreditCore.Repo

  @shortdoc "Sanity-checks the currently configured MFA encryption key"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    users =
      Repo.all(
        from u in User,
          where: u.totp_secret_version >= 1 and not is_nil(u.totp_secret)
      )

    case users do
      [] ->
        Mix.shell().info("No encrypted TOTP secrets found to check.")

      users ->
        {ok, failed} = check_users(users)
        Mix.shell().info("#{length(ok)}/#{length(users)} decrypted successfully.")

        if failed != [] do
          Mix.shell().error(
            "Failed to decrypt user id(s): #{Enum.map_join(failed, ", ", & &1.id)}"
          )

          System.halt(1)
        end
    end
  end

  defp check_users(users) do
    Enum.split_with(users, fn user ->
      try do
        is_binary(Accounts.decode_totp_secret_for_check(user))
      rescue
        _ -> false
      end
    end)
  end
end
