defmodule MiwayCreditCoreWeb.SystemHealthControllerTest do
  # Touches Monitoring.Store's process-global ETS table (via record_tick
  # in setup) — async: false + reset in setup.
  use MiwayCreditCoreWeb.ConnCase, async: false

  import MiwayCreditCore.{AccountsFixtures, OrganisationsFixtures}

  alias MiwayCreditCore.Monitoring
  alias MiwayCreditCore.Monitoring.Store

  setup do
    Store.reset!()
    :ok
  end

  test "a platform administrator sees real diagnostics", %{conn: conn} do
    admin = admin_fixture()
    Monitoring.record_tick(:arrears_scheduler)

    conn = conn |> login(admin) |> get(~p"/admin/system-health")

    response = html_response(conn, 200)
    assert response =~ "System Health"
    assert response =~ "Arrears Scheduler"
    assert response =~ "KYC Retention Scheduler"
  end

  test "an organisation administrator gets a real 403, not a leak", %{conn: conn} do
    organisation = organisation_fixture()
    org_admin = staff_member_in_organisation_fixture(organisation, "organisation_administrator")

    conn = conn |> login(org_admin) |> get(~p"/admin/system-health")

    assert html_response(conn, 403)
  end

  test "a loan officer gets a real 403", %{conn: conn} do
    organisation = organisation_fixture()
    loan_officer = staff_member_in_organisation_fixture(organisation, "loan_officer")

    conn = conn |> login(loan_officer) |> get(~p"/admin/system-health")

    assert html_response(conn, 403)
  end

  test "an unauthenticated request is redirected to login", %{conn: conn} do
    conn = get(conn, ~p"/admin/system-health")
    assert redirected_to(conn) == ~p"/login"
  end

  defp login(conn, user) do
    conn
    |> Plug.Conn.put_session(:user_id, user.id)
    |> Plug.Conn.put_session(:authenticated_at, NaiveDateTime.utc_now())
  end
end
