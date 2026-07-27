defmodule MiwayCreditCoreWeb.TwoFactorControllerTest do
  use MiwayCreditCoreWeb.ConnCase, async: true

  import MiwayCreditCore.CustomersFixtures
  import MiwayCreditCore.AccountsFixtures

  alias MiwayCreditCore.Accounts

  @password "CorrectHorse123"

  test "confirming a correct code logs a staff member in and redirects to /admin/dashboard", %{conn: conn} do
    user = staff_member_fixture("loan_officer", %{password: @password})
    secret = Accounts.generate_totp_secret()
    {:ok, user} = Accounts.enable_totp(user, secret)

    conn = conn |> Plug.Conn.put_session(:pending_2fa_user_id, user.id)
    code = NimbleTOTP.verification_code(secret)

    conn = post(conn, ~p"/login/verify", totp: %{code: code})
    assert redirected_to(conn) == ~p"/admin/dashboard"
    assert get_session(conn, :user_id) == user.id
  end

  test "confirming a correct code logs a customer in and redirects to /client/dashboard", %{conn: conn} do
    customer = customer_fixture()
    user = customer_user_fixture(customer, %{password: @password})
    secret = Accounts.generate_totp_secret()
    {:ok, user} = Accounts.enable_totp(user, secret)

    conn = conn |> Plug.Conn.put_session(:pending_2fa_user_id, user.id)
    code = NimbleTOTP.verification_code(secret)

    conn = post(conn, ~p"/login/verify", totp: %{code: code})
    assert redirected_to(conn) == ~p"/client/dashboard"
  end

  test "an invalid code re-renders the verify page", %{conn: conn} do
    user = staff_member_fixture("loan_officer", %{password: @password})
    secret = Accounts.generate_totp_secret()
    {:ok, user} = Accounts.enable_totp(user, secret)

    conn = conn |> Plug.Conn.put_session(:pending_2fa_user_id, user.id)
    conn = post(conn, ~p"/login/verify", totp: %{code: "000000"})
    assert html_response(conn, 200) =~ "Invalid code"
  end

  test "no pending 2FA session redirects to /login", %{conn: conn} do
    conn = get(conn, ~p"/login/verify")
    assert redirected_to(conn) == ~p"/login"
  end
end
