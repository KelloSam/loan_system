defmodule MiwayCreditCoreWeb.TwoFactorControllerTest do
  use MiwayCreditCoreWeb.ConnCase, async: true

  import MiwayCreditCore.CustomersFixtures
  import MiwayCreditCore.AccountsFixtures

  alias MiwayCreditCore.Accounts

  @password "CorrectHorse123"

  # Every test in this module posts to /login/verify, which is now
  # IP-throttled (RateLimitPlug) on top of the account-lockout tests
  # below doing several posts each — reset the shared ETS counter
  # before every test so none of them can be pushed over the throttle
  # by another test's requests landing in the same 60s window.
  setup do
    PlugAttack.Storage.Ets.clean(MiwayCreditCoreWeb.RateLimitStorage)
    :ok
  end

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

  describe "brute-force protection" do
    setup do
      PlugAttack.Storage.Ets.clean(MiwayCreditCoreWeb.RateLimitStorage)
      :ok
    end

    test "5 wrong TOTP codes lock the account; a 6th attempt with the correct code is refused", %{conn: conn} do
      user = staff_member_fixture("loan_officer", %{password: @password})
      secret = Accounts.generate_totp_secret()
      {:ok, user} = Accounts.enable_totp(user, secret)
      code = NimbleTOTP.verification_code(secret)

      attempt = fn totp_code ->
        conn
        |> Plug.Conn.put_session(:pending_2fa_user_id, user.id)
        |> then(&post(&1, ~p"/login/verify", totp: %{code: totp_code}))
      end

      last_wrong = Enum.reduce(1..5, nil, fn _, _ -> attempt.("000000") end)
      assert html_response(last_wrong, 200) =~ "Invalid code"

      locked = attempt.(code)
      assert html_response(locked, 200) =~ "Account locked"
      refute get_session(locked, :user_id)
    end

    test "a pre-locked account is refused at /login/verify even with the correct code", %{conn: conn} do
      user = staff_member_fixture("loan_officer", %{password: @password})
      secret = Accounts.generate_totp_secret()
      {:ok, user} = Accounts.enable_totp(user, secret)
      code = NimbleTOTP.verification_code(secret)

      user =
        Enum.reduce(1..5, user, fn _, acc ->
          {:ok, updated} = Accounts.increment_failed_attempts(acc)
          updated
        end)

      assert Accounts.account_locked?(user)

      conn = conn |> Plug.Conn.put_session(:pending_2fa_user_id, user.id)
      conn = post(conn, ~p"/login/verify", totp: %{code: code})

      assert html_response(conn, 200) =~ "Account locked"
      refute get_session(conn, :user_id)
    end
  end
end
