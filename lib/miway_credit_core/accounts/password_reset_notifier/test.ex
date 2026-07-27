defmodule MiwayCreditCore.Accounts.PasswordResetNotifier.Test do
  @moduledoc "Sends the reset link to the calling test process for assertions."
  @behaviour MiwayCreditCore.Accounts.PasswordResetNotifier

  @impl true
  def deliver_reset_link(user, reset_url) do
    send(self(), {:password_reset_link, user, reset_url})
    :ok
  end
end
