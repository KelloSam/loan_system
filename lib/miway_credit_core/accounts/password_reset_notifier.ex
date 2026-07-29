defmodule MiwayCreditCore.Accounts.PasswordResetNotifier do
  @moduledoc """
  Delivery boundary for password-reset links. Real email/SMS sending
  is deliberately deferred to when the reserved `Notifications`
  context (see docs/architecture/context_boundaries.md) is actually
  built — this behaviour exists so Accounts can generate and validate
  reset tokens now without jumping ahead of that boundary.

  Configured via `config :miway_credit_core, :password_reset_notifier,
  Adapter`. No adapter is configured by default in production — an
  unconfigured adapter fails the delivery attempt (logged, not
  surfaced to the requester) rather than silently pretending to send.
  """

  @callback deliver_reset_link(user :: struct(), reset_url :: String.t()) ::
              :ok | {:error, term()}

  def deliver_reset_link(user, reset_url) do
    adapter().deliver_reset_link(user, reset_url)
  end

  @doc """
  Whether a real delivery adapter is configured. Deployment-config
  information, not per-request/per-user data — safe to branch UI copy
  on without creating an email-enumeration leak.
  """
  def configured?, do: adapter() != MiwayCreditCore.Accounts.PasswordResetNotifier.Unconfigured

  defp adapter do
    Application.get_env(
      :miway_credit_core,
      :password_reset_notifier,
      MiwayCreditCore.Accounts.PasswordResetNotifier.Unconfigured
    )
  end
end
