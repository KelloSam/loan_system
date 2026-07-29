defmodule MiwayCreditCoreWeb.HealthControllerTest do
  use MiwayCreditCoreWeb.ConnCase, async: true

  test "GET /up returns 200 with a minimal ok body", %{conn: conn} do
    conn = get(conn, ~p"/up")
    assert json_response(conn, 200) == %{"status" => "ok"}
  end
end
