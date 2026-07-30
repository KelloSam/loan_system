defmodule MiwayCreditCore.Accounts.PasswordResetNotifier.Email do
  @moduledoc """
  Real email delivery, via the `Notifications` context boundary.
  Accounts stays in charge of the token — this adapter only hands the
  already-built reset URL over for delivery and returns whatever
  `Notifications` reports.
  """
  @behaviour MiwayCreditCore.Accounts.PasswordResetNotifier

  alias MiwayCreditCore.Notifications

  @impl true
  def deliver_reset_link(user, reset_url) do
    Notifications.deliver_password_reset_email(user, reset_url)
  end
end
