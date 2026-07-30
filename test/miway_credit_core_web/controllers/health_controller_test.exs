defmodule MiwayCreditCoreWeb.HealthControllerTest do
  use MiwayCreditCoreWeb.ConnCase, async: true

  test "GET /up returns 200 with a minimal ok body", %{conn: conn} do
    conn = get(conn, ~p"/up")
    assert json_response(conn, 200) == %{"status" => "ok"}
  end

  test "GET /ready returns 200 when the database is reachable", %{conn: conn} do
    conn = get(conn, ~p"/ready")
    assert json_response(conn, 200) == %{"status" => "ready"}
  end

  test "GET /ready returns 503 with no internal detail when the database is unavailable" do
    # Plain spawn (unlike Task.async) doesn't propagate $callers, so this
    # process is never sandbox-allowed and the Repo call hits a real
    # DBConnection.OwnershipError instead of succeeding.
    parent = self()

    spawn(fn ->
      send(parent, {:ready_response, get(Phoenix.ConnTest.build_conn(), ~p"/ready")})
    end)

    assert_receive {:ready_response, conn}, 5_000
    assert json_response(conn, 503) == %{"status" => "unavailable"}
  end
end
