defmodule MiwayCreditCore.Accounts.PasswordResetNotifier.Unconfigured do
  @moduledoc """
  The default when no adapter is configured (production, until a real
  provider is wired up). Fails the delivery attempt loudly in the logs
  rather than pretending to send — the caller (Accounts.request_password_reset/1)
  still returns :ok to the requester either way, so this never leaks
  whether an email exists.
  """
  @behaviour MiwayCreditCore.Accounts.PasswordResetNotifier

  require Logger

  @impl true
  def deliver_reset_link(user, _reset_url) do
    Logger.error("Password reset requested for #{user.email} but no PasswordResetNotifier adapter is configured")
    {:error, :not_configured}
  end
end
