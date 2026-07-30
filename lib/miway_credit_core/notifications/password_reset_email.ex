defmodule MiwayCreditCore.Notifications.PasswordResetEmail do
  @moduledoc """
  Builds the password-reset email. The reset link is the only
  sensitive value in this message — the token it embeds is exactly
  what lets the recipient reset the password, so it belongs here by
  design; nothing else about the account (status, role, other
  identifying detail) is included.
  """

  import Swoosh.Email

  @validity_minutes 60

  def build(user, reset_url) do
    new()
    |> to(user.email)
    |> from({from_name(), from_address()})
    |> subject("Reset your Miway CreditCore password")
    |> text_body(text_body(reset_url))
    |> html_body(html_body(reset_url))
  end

  defp text_body(reset_url) do
    """
    We received a request to reset the password on this account.

    Reset your password: #{reset_url}

    This link expires in #{@validity_minutes} minutes and can only be used once.

    If you didn't request this, you can safely ignore this email — your password will not be changed.
    """
  end

  defp html_body(reset_url) do
    """
    <p>We received a request to reset the password on this account.</p>
    <p><a href="#{reset_url}">Reset your password</a></p>
    <p>This link expires in #{@validity_minutes} minutes and can only be used once.</p>
    <p>If you didn't request this, you can safely ignore this email — your password will not be changed.</p>
    """
  end

  defp from_address, do: Application.fetch_env!(:miway_credit_core, :mail_from_address)
  defp from_name, do: Application.get_env(:miway_credit_core, :mail_from_name, "Miway CreditCore")
end
