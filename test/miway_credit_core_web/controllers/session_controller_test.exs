defmodule MiwayCreditCoreWeb.SessionControllerTest do
  use MiwayCreditCoreWeb.ConnCase, async: true

  import MiwayCreditCore.CustomersFixtures
  import MiwayCreditCore.AccountsFixtures

  alias MiwayCreditCore.Accounts

  @password "CorrectHorse123"

  test "staff login redirects to /admin/dashboard", %{conn: conn} do
    user = staff_member_fixture("loan_officer", %{password: @password})

    conn = post(conn, ~p"/login", session: %{email: user.email, password: @password})
    assert redirected_to(conn) == ~p"/admin/dashboard"
  end

  test "customer login redirects to /client/dashboard", %{conn: conn} do
    customer = customer_fixture()
    user = customer_user_fixture(customer, %{password: @password})

    conn = post(conn, ~p"/login", session: %{email: user.email, password: @password})
    assert redirected_to(conn) == ~p"/client/dashboard"
  end

  test "invalid credentials render the login page with an error", %{conn: conn} do
    user = staff_member_fixture("loan_officer", %{password: @password})

    conn = post(conn, ~p"/login", session: %{email: user.email, password: "WrongPassword1"})
    assert html_response(conn, 200) =~ "Invalid email or password."
  end

  test "a 2FA-enabled user is held pending until verification", %{conn: conn} do
    user = staff_member_fixture("loan_officer", %{password: @password})
    secret = Accounts.generate_totp_secret()
    {:ok, user} = Accounts.enable_totp(user, secret)

    conn = post(conn, ~p"/login", session: %{email: user.email, password: @password})
    assert redirected_to(conn) == ~p"/login/verify"
  end
end
