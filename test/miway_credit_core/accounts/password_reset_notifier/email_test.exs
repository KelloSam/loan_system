defmodule MiwayCreditCore.Accounts.PasswordResetNotifier.EmailTest do
  use ExUnit.Case, async: true

  import Swoosh.TestAssertions

  alias MiwayCreditCore.Accounts.PasswordResetNotifier

  test "deliver_reset_link/2 delegates to Notifications and sends a real email" do
    user = %{email: "delegate-target@example.com"}
    reset_url = "http://localhost:4001/password-reset/another-token"

    assert :ok = PasswordResetNotifier.Email.deliver_reset_link(user, reset_url)
    assert_email_sent(subject: "Reset your Miway CreditCore password")
  end
end
