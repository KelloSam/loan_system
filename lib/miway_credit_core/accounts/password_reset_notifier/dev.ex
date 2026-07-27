defmodule MiwayCreditCore.Accounts.PasswordResetNotifier.Dev do
  @moduledoc "Logs the reset link instead of sending an email. Used in dev."
  @behaviour MiwayCreditCore.Accounts.PasswordResetNotifier

  require Logger

  @impl true
  def deliver_reset_link(user, reset_url) do
    Logger.info("Password reset requested for #{user.email}: #{reset_url}")
    :ok
  end
end
