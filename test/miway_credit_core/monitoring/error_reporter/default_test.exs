defmodule MiwayCreditCore.Monitoring.ErrorReporter.DefaultTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias MiwayCreditCore.Monitoring.ErrorReporter.Default

  test "logs a structured, greppable error line including the exception message and status" do
    reason = %RuntimeError{message: "boom"}
    stacktrace = []
    metadata = %{status: 500}

    log = capture_log(fn -> Default.report(:error, reason, stacktrace, metadata) end)

    assert log =~ "[error_reporter]"
    assert log =~ "boom"
    assert log =~ "status=500"
  end

  test "never raises even when metadata has no :status" do
    assert Default.report(:error, %RuntimeError{message: "boom"}, [], %{}) == :ok
  end
end
