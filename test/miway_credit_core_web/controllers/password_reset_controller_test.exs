defmodule MiwayCreditCoreWeb.PasswordResetControllerTest do
  use MiwayCreditCoreWeb.ConnCase, async: true

  import MiwayCreditCore.AccountsFixtures

  alias MiwayCreditCore.Accounts

  test "create/2 gives the same response whether or not the email exists", %{conn: conn} do
    user = user_fixture()

    conn1 = post(conn, ~p"/password-reset", password_reset: %{email: user.email})
    assert_receive {:password_reset_link, _user, _url}
    msg1 = Phoenix.Flash.get(conn1.assigns.flash, :info)

    conn2 = post(conn, ~p"/password-reset", password_reset: %{email: "nobody@example.com"})
    refute_receive {:password_reset_link, _, _}
    msg2 = Phoenix.Flash.get(conn2.assigns.flash, :info)

    assert msg1 == msg2
  end

  test "edit/2 renders the set-password form for a valid token", %{conn: conn} do
    user = user_fixture()
    {raw_token, url} = request_reset(user)
    assert url =~ raw_token

    conn = get(conn, ~p"/password-reset/#{raw_token}")
    assert html_response(conn, 200) =~ "New Password"
  end

  test "edit/2 redirects for an invalid token", %{conn: conn} do
    conn = get(conn, ~p"/password-reset/not-a-real-token")
    assert redirected_to(conn) == ~p"/password-reset"
  end

  test "update/2 resets the password and lets the user log in with it", %{conn: conn} do
    user = user_fixture(%{password: "OriginalPassword1"})
    {raw_token, _url} = request_reset(user)

    conn = put(conn, ~p"/password-reset/#{raw_token}", password_reset: %{password: "BrandNewPassword1"})
    assert redirected_to(conn) == ~p"/login"

    assert {:ok, _} = Accounts.authenticate_user(user.email, "BrandNewPassword1")
  end

  test "update/2 rejects reusing a token that already reset the password", %{conn: conn} do
    user = user_fixture()
    {raw_token, _url} = request_reset(user)

    put(conn, ~p"/password-reset/#{raw_token}", password_reset: %{password: "BrandNewPassword1"})
    conn2 = put(conn, ~p"/password-reset/#{raw_token}", password_reset: %{password: "AnotherPassword1"})

    assert redirected_to(conn2) == ~p"/password-reset"
  end

  defp request_reset(user) do
    Accounts.request_password_reset(user.email, &"http://localhost/password-reset/#{&1}")
    assert_receive {:password_reset_link, _user, url}
    raw_token = url |> String.split("/") |> List.last()
    {raw_token, url}
  end
end
