defmodule MiwayCreditCoreWeb.ErrorReportingTest do
  # End-to-end: a real request through the actual router/endpoint,
  # not a direct call to the telemetry handler — proves the
  # [:phoenix, :error_rendered] attach point in
  # MiwayCreditCore.Monitoring.attach_telemetry_handlers/0 is genuinely
  # wired up (it's attached once, for real, from Application.start/2).
  use MiwayCreditCoreWeb.ConnCase, async: true

  import ExUnit.CaptureLog

  test "an unhandled 404 is captured and reported", %{conn: conn} do
    log =
      capture_log(fn ->
        conn = get(conn, "/this-route-does-not-exist")
        assert conn.status == 404
      end)

    assert log =~ "[error_reporter]"
    assert log =~ "NoRouteError"
  end
end
