defmodule MiwayCreditCoreWeb.CustomerLoanControllerTest do
  use MiwayCreditCoreWeb.ConnCase, async: true

  import MiwayCreditCore.CustomersFixtures
  import MiwayCreditCore.LoansFixtures
  import MiwayCreditCore.AccountsFixtures
  import MiwayCreditCore.OrganisationsFixtures

  test "index lists only the current customer's applications", %{conn: conn} do
    customer = customer_fixture()
    user = customer_user_fixture(customer)
    mine = application_fixture(%{"customer_id" => customer.id})
    _someone_elses = application_fixture()

    conn = conn |> login(user) |> get(~p"/client/loans")

    body = html_response(conn, 200)
    assert body =~ mine.id
  end

  test "show renders an application belonging to the current customer", %{conn: conn} do
    customer = customer_fixture()
    user = customer_user_fixture(customer)
    application = application_fixture(%{"customer_id" => customer.id})

    conn = conn |> login(user) |> get(~p"/client/loans/#{application.id}")
    assert html_response(conn, 200)
  end

  test "show refuses an application belonging to a different customer in the same organisation", %{conn: conn} do
    organisation = organisation_fixture()
    customer = customer_fixture_in_organisation(organisation)
    other_customer = customer_fixture_in_organisation(organisation)
    user = customer_user_fixture(customer)
    other_application = application_fixture(%{"customer_id" => other_customer.id})

    conn = conn |> login(user) |> get(~p"/client/loans/#{other_application.id}")
    assert redirected_to(conn) == ~p"/client/loans"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "not authorized"
  end

  test "a login with no CustomerUser is refused by the /client pipeline", %{conn: conn} do
    user = user_fixture()
    conn = conn |> login(user) |> get(~p"/client/loans")
    assert redirected_to(conn) == "/login"
  end

  defp login(conn, user) do
    conn
    |> Plug.Conn.put_session(:user_id, user.id)
    |> Plug.Conn.put_session(:authenticated_at, NaiveDateTime.utc_now())
  end
end
