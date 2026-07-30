defmodule MiwayCreditCore.NotificationsTest do
  use ExUnit.Case, async: true

  import Swoosh.TestAssertions

  alias MiwayCreditCore.Notifications
  alias MiwayCreditCore.Support.FailingMailAdapter

  @user %{email: "reset-target@example.com"}
  @reset_url "http://localhost:4001/password-reset/some-raw-token"

  test "delivers the reset link email and returns :ok on success" do
    assert :ok = Notifications.deliver_password_reset_email(@user, @reset_url)

    assert_email_sent(fn email ->
      assert email.subject =~ "Reset your"
      assert Enum.any?(email.to, fn {_name, address} -> address == @user.email end)
      assert email.text_body =~ @reset_url
      assert email.html_body =~ @reset_url
      assert email.text_body =~ "expires in 60 minutes"
    end)
  end

  test "never puts the raw token anywhere except inside the link itself" do
    Notifications.deliver_password_reset_email(@user, @reset_url)

    assert_email_sent(fn email ->
      token = @reset_url |> String.split("/") |> List.last()
      # every occurrence of the token in the body is part of the URL, not standalone
      assert email.text_body |> String.split(token) |> Enum.count() == 2
    end)
  end

  test "returns {:error, reason} and never raises when the provider fails" do
    assert {:error, :provider_unreachable} =
             Notifications.deliver_password_reset_email(@user, @reset_url,
               adapter: FailingMailAdapter
             )
  end

  test "logs delivery failures server-side without crashing the caller" do
    import ExUnit.CaptureLog

    log =
      capture_log(fn ->
        Notifications.deliver_password_reset_email(@user, @reset_url, adapter: FailingMailAdapter)
      end)

    assert log =~ "Password reset email delivery failed"
    assert log =~ @user.email
  end
end
