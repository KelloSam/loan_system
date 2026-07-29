defmodule MiwayCreditCoreWeb.HealthControllerTest do
  use MiwayCreditCoreWeb.ConnCase, async: true

  test "GET /up returns 200 with a minimal ok body", %{conn: conn} do
    conn = get(conn, ~p"/up")
    assert json_response(conn, 200) == %{"status" => "ok"}
  end

  test "GET /ready returns 200 when the database is reachable", %{conn: conn} do
    conn = get(conn, ~p"/ready")
    assert json_response(conn, 200) == %{"status" => "ok"}
  end
end
