defmodule MiwayCreditCore.ArrearsSchedulerTest do
  # Calls handle_info/2 directly rather than starting the (test-disabled)
  # GenServer — runs inside the test's own sandboxed process, and lets
  # this test assert on the heartbeat side effect without touching a
  # real background process. Monitoring.Store's ETS table is
  # process-global for the suite, so async: false + reset in setup.
  use MiwayCreditCore.DataCase, async: false

  alias MiwayCreditCore.ArrearsScheduler
  alias MiwayCreditCore.Monitoring
  alias MiwayCreditCore.Monitoring.Store

  setup do
    Store.reset!()
    :ok
  end

  test "a successful tick records a heartbeat and reschedules itself" do
    assert Monitoring.last_tick(:arrears_scheduler) == :never

    assert {:noreply, %{interval_ms: 999_999_999}} =
             ArrearsScheduler.handle_info(:check_overdue, %{interval_ms: 999_999_999})

    assert {:ok, %DateTime{}} = Monitoring.last_tick(:arrears_scheduler)
  end
end
