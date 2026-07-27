defmodule MiwayCreditCoreWeb.Plugs.AuthPlugTest do
  use MiwayCreditCoreWeb.ConnCase, async: true

  import MiwayCreditCore.CustomersFixtures
  import MiwayCreditCore.AccountsFixtures

  alias MiwayCreditCoreWeb.Plugs.AuthPlug
  alias MiwayCreditCore.{Accounts, Repo}
  alias MiwayCreditCore.Accounts.User

  test "redirects to /login when the session is empty", %{conn: conn} do
    conn = AuthPlug.call(conn, [])
    assert conn.halted
    assert redirected_to(conn) == "/login"
  end

  test "assigns current_user and current_staff_member for a staff login", %{conn: conn} do
    user = staff_member_fixture("loan_officer")
    conn = authenticated_conn(conn, user) |> AuthPlug.call([])

    refute conn.halted
    assert conn.assigns.current_user.id == user.id
    assert conn.assigns.current_staff_member.role == "loan_officer"
    assert conn.assigns.current_customer == nil
  end

  test "assigns current_customer for a customer-portal login", %{conn: conn} do
    customer = customer_fixture()
    user = customer_user_fixture(customer)
    conn = authenticated_conn(conn, user) |> AuthPlug.call([])

    refute conn.halted
    assert conn.assigns.current_customer.id == customer.id
    assert conn.assigns.current_staff_member == nil
  end

  test "redirects a suspended user to /login", %{conn: conn} do
    user = staff_member_fixture("loan_officer")
    {:ok, _} = Accounts.update_user_status(user, "suspended")

    conn = authenticated_conn(conn, user) |> AuthPlug.call([])
    assert conn.halted
    assert redirected_to(conn) == "/login"
  end

  test "redirects when the session predates sessions_invalidated_at", %{conn: conn} do
    user = staff_member_fixture("loan_officer")

    stale_authenticated_at =
      NaiveDateTime.utc_now() |> NaiveDateTime.add(-3600, :second) |> NaiveDateTime.truncate(:second)

    {:ok, _} =
      user
      |> User.session_changeset(%{sessions_invalidated_at: NaiveDateTime.utc_now()})
      |> Repo.update()

    conn =
      conn
      |> Plug.Conn.put_session(:user_id, user.id)
      |> Plug.Conn.put_session(:authenticated_at, stale_authenticated_at)
      |> AuthPlug.call([])

    assert conn.halted
    assert redirected_to(conn) == "/login"
  end

  defp authenticated_conn(conn, user) do
    conn
    |> Plug.Conn.put_session(:user_id, user.id)
    |> Plug.Conn.put_session(:authenticated_at, NaiveDateTime.utc_now())
  end
end
