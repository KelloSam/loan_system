defmodule MiwayCreditCoreWeb.Plugs.EnsureCustomerPlugTest do
  use MiwayCreditCoreWeb.ConnCase, async: true

  alias MiwayCreditCoreWeb.Plugs.EnsureCustomerPlug

  test "passes through when current_customer is assigned", %{conn: conn} do
    conn = conn |> assign(:current_customer, %{id: "1"}) |> EnsureCustomerPlug.call([])
    refute conn.halted
  end

  test "redirects to /login when current_customer is nil", %{conn: conn} do
    conn = conn |> assign(:current_customer, nil) |> EnsureCustomerPlug.call([])
    assert conn.halted
    assert redirected_to(conn) == "/login"
  end
end
