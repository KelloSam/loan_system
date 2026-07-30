defmodule MiwayCreditCore.MonitoringTest do
  # The Store's ETS table is process-global for the whole suite (same
  # class of shared state as PlugAttack's rate-limit counter) — must
  # run async: false with an explicit reset in setup.
  use MiwayCreditCore.DataCase, async: false

  alias MiwayCreditCore.Monitoring
  alias MiwayCreditCore.Monitoring.Store

  setup do
    Store.reset!()
    :ok
  end

  describe "scheduler heartbeats" do
    test "last_tick/1 is :never before any tick is recorded" do
      assert Monitoring.last_tick(:arrears_scheduler) == :never
    end

    test "record_tick/1 makes last_tick/1 return the recorded time" do
      Monitoring.record_tick(:arrears_scheduler)
      assert {:ok, %DateTime{} = last} = Monitoring.last_tick(:arrears_scheduler)
      assert DateTime.diff(DateTime.utc_now(), last) < 5
    end

    test "stale?/2 is true when never ticked" do
      assert Monitoring.stale?(:kyc_retention_scheduler, 60)
    end

    test "stale?/2 is false right after a tick, true once the max age elapses" do
      Monitoring.record_tick(:arrears_scheduler)
      refute Monitoring.stale?(:arrears_scheduler, 60)

      :ets.insert(Store.table(), {{:tick, :arrears_scheduler}, System.system_time(:second) - 120})
      assert Monitoring.stale?(:arrears_scheduler, 60)
    end
  end

  describe "scanner failure counter" do
    test "recent_scanner_failure_count/1 increases by exactly one per recorded failure" do
      before = Monitoring.recent_scanner_failure_count()
      Monitoring.record_scanner_failure(:scanner_unavailable)
      assert Monitoring.recent_scanner_failure_count() == before + 1
    end

    test "recent_scanner_failure_count/1 excludes failures older than the window" do
      before = Monitoring.recent_scanner_failure_count(60)
      key = {:scanner_failure, System.unique_integer([:positive, :monotonic])}
      :ets.insert(Store.table(), {key, System.system_time(:second) - 120, :scanner_unavailable})
      assert Monitoring.recent_scanner_failure_count(60) == before
    end
  end

  describe "disk_free_bytes/1" do
    test "returns a positive byte count for a real directory" do
      assert {:ok, bytes} = Monitoring.disk_free_bytes(System.tmp_dir!())
      assert is_integer(bytes) and bytes > 0
    end

    test "returns an error for a path that doesn't exist" do
      assert Monitoring.disk_free_bytes("/nonexistent/#{Ecto.UUID.generate()}") ==
               {:error, :path_not_found}
    end
  end
end
