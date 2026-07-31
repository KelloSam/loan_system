defmodule MiwayCreditCore.MonitoringTest do
  # The Store's ETS table is process-global for the whole suite (same
  # class of shared state as PlugAttack's rate-limit counter) — must
  # run async: false with an explicit reset in setup.
  use MiwayCreditCore.DataCase, async: false

  import ExUnit.CaptureLog

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

    test "last_scanner_failure_at/0 is :never before any failure, then the most recent failure's time" do
      assert Monitoring.last_scanner_failure_at() == :never

      Monitoring.record_scanner_failure(:scanner_unavailable)
      assert {:ok, %DateTime{} = first} = Monitoring.last_scanner_failure_at()

      Monitoring.record_scanner_failure(:scanner_unavailable)
      assert {:ok, %DateTime{} = second} = Monitoring.last_scanner_failure_at()
      assert DateTime.compare(second, first) in [:eq, :gt]
    end
  end

  describe "pool_stats/0 and record_query_sample/1" do
    test "starts empty after a reset" do
      assert %{
               sample_count: 0,
               last_queue_time_ms: nil,
               max_queue_time_ms: nil,
               max_queue_time_window_started_at: :never
             } = Monitoring.pool_stats()
    end

    test "tracks sample count, last, running max, and starts the max window on the first sample" do
      Monitoring.record_query_sample(5)
      Monitoring.record_query_sample(20)
      Monitoring.record_query_sample(3)

      assert %{
               sample_count: 3,
               last_queue_time_ms: 3,
               max_queue_time_ms: 20,
               max_queue_time_window_started_at: {:ok, %DateTime{}}
             } = Monitoring.pool_stats()
    end

    test "pool_healthy?/0 is true below the warning threshold, false at or above it" do
      Monitoring.record_query_sample(1)
      assert Monitoring.pool_healthy?()

      Monitoring.record_query_sample(Monitoring.pool_stats().warning_threshold_ms)
      refute Monitoring.pool_healthy?()
    end
  end

  describe "handle_repo_query/4 (the telemetry handler)" do
    test "records a sample when :queue_time is present, converting native time to ms" do
      one_ms_native = System.convert_time_unit(1, :millisecond, :native)

      Monitoring.handle_repo_query(
        [:miway_credit_core, :repo, :query],
        %{queue_time: one_ms_native},
        %{},
        nil
      )

      assert %{sample_count: 1, last_queue_time_ms: 1} = Monitoring.pool_stats()
    end

    test "is a no-op, not a crash, when :queue_time is absent" do
      assert Monitoring.handle_repo_query([:miway_credit_core, :repo, :query], %{}, %{}, nil) ==
               :ok

      assert Monitoring.pool_stats().sample_count == 0
    end

    test "never raises even given measurements that would break unit conversion" do
      assert Monitoring.handle_repo_query(
               [:miway_credit_core, :repo, :query],
               %{queue_time: :not_a_number},
               %{},
               nil
             ) == :ok

      assert Monitoring.pool_stats().sample_count == 0
    end

    test "a real Repo query, live, fires the attached telemetry handler and increases the sample count" do
      before = Monitoring.pool_stats().sample_count
      MiwayCreditCore.Repo.query!("SELECT 1")
      assert Monitoring.pool_stats().sample_count > before
    end
  end

  describe "handle_error_rendered/4 (the telemetry handler)" do
    test "forwards to the configured ErrorReporter" do
      metadata = %{
        kind: :error,
        reason: %RuntimeError{message: "boom"},
        stacktrace: [],
        status: 500
      }

      log =
        capture_log(fn ->
          Monitoring.handle_error_rendered([:phoenix, :error_rendered], %{}, metadata, nil)
        end)

      assert log =~ "[error_reporter]"
      assert log =~ "boom"
    end

    test "never raises even given metadata missing the keys it expects" do
      capture_log(fn ->
        assert Monitoring.handle_error_rendered([:phoenix, :error_rendered], %{}, %{}, nil) == :ok
      end)
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

  # No dedicated test for record_tick/1, record_scanner_failure/1, or
  # record_query_sample/1's rescue/catch wrapping itself: their bodies
  # are 1-3 plain :ets.insert/update_counter calls against values that
  # are always well-formed by construction (nothing about a caller's
  # input can make an :ets.insert with a valid table raise), so the
  # only realistic trigger is Store's table not existing at all — and
  # deliberately deleting/replacing the real shared Store table to
  # simulate that was tried and reverted: the replacement table ends
  # up owned by the *test* process rather than Store's own GenServer,
  # so it's destroyed the instant that test exits, corrupting every
  # later test in the suite (reproduced live: 13 unrelated failures
  # elsewhere). The `handle_repo_query/4`/`handle_error_rendered/4`
  # tests above already prove this exact rescue/catch pattern works
  # against a real trigger — same construct, read the source for the
  # rest.
end
