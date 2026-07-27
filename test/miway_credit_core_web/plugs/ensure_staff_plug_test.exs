defmodule MiwayCreditCoreWeb.Plugs.EnsureStaffPlugTest do
  use MiwayCreditCoreWeb.ConnCase, async: true

  alias MiwayCreditCoreWeb.Plugs.EnsureStaffPlug

  test "passes through when current_staff_member is assigned", %{conn: conn} do
    conn = conn |> assign(:current_staff_member, %{id: "1"}) |> EnsureStaffPlug.call([])
    refute conn.halted
  end

  test "redirects to /login when current_staff_member is nil", %{conn: conn} do
    conn = conn |> assign(:current_staff_member, nil) |> EnsureStaffPlug.call([])
    assert conn.halted
    assert redirected_to(conn) == "/login"
  end
end
