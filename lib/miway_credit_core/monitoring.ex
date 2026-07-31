defmodule MiwayCreditCore.Monitoring do
  @moduledoc """
  Operational self-checks — runbook §11's "Monitoring" checklist.
  State lives in `MiwayCreditCore.Monitoring.Store`'s ETS table, owned
  by a process supervised separately from any writer (a scheduler
  tick, a telemetry handler, `MalwareScanner`), so it survives any
  *writer* crashing and restarting. It does NOT survive `Store`'s own
  crash (a fresh empty table is created on restart — see `Store`'s
  moduledoc), an application/VM/container/host restart, or apply
  across more than one running instance in a multi-server deployment —
  this is a runtime indicator, not a permanent record; `AuditLogs`
  (backed by Postgres) is the durable trail.

  The table is `:public` rather than `:protected` deliberately: five
  independent processes (two schedulers, `MalwareScanner`, and two
  telemetry handlers) each write directly, matching the exact
  multi-writer pattern this codebase's own `PlugAttack.Storage.Ets`
  already uses for the same reason (routing every write through a
  single GenServer call would serialize otherwise-independent writers
  for no correctness benefit). Every write in this codebase goes
  through this module's public functions below — nothing reaches into
  `Store`'s table directly — so treat that as the enforced boundary
  instead.

  Every public write function here (`record_tick/1`,
  `record_scanner_failure/1`, `record_query_sample/1`) is wrapped so a
  `Store` hiccup can never raise into its caller: some of those
  callers (`MalwareScanner.scan/1`, in particular) sit directly in a
  customer-facing KYC upload path, and a monitoring subsystem must
  never be able to break the business operation it's observing.
  """

  require Logger

  alias MiwayCreditCore.Monitoring.ErrorReporter
  alias MiwayCreditCore.Monitoring.Store

  @scheduler_names [:arrears_scheduler, :kyc_retention_scheduler, :backup_scheduler]
  @repo_query_event [:miway_credit_core, :repo, :query]
  @error_rendered_event [:phoenix, :error_rendered]

  # Milliseconds of (windowed max) queue time at or above this is
  # flagged on /admin/system-health — an operator-facing threshold,
  # not an alert (see pool_healthy?/1).
  @pool_queue_time_warning_ms 200

  @doc "The scheduler names this module tracks heartbeats for."
  def scheduler_names, do: @scheduler_names

  @doc "Records a successful tick. Called as the last line of a scheduler's successful `handle_info` body — a tick that raises earlier never reaches this call, which is the staleness signal. Never raises: a Store hiccup here must not crash the scheduler that just did real work."
  def record_tick(scheduler_name) when scheduler_name in @scheduler_names do
    :ets.insert(Store.table(), {{:tick, scheduler_name}, System.system_time(:second)})
    :ok
  rescue
    error -> log_write_failure("record_tick", error)
  catch
    kind, reason -> log_write_failure("record_tick", {kind, reason})
  end

  @doc "The last recorded successful tick, or `:never` if none has been recorded since the table was last reset (fresh boot, or test reset)."
  def last_tick(scheduler_name) do
    case :ets.lookup(Store.table(), {:tick, scheduler_name}) do
      [{_key, timestamp}] -> {:ok, DateTime.from_unix!(timestamp)}
      [] -> :never
    end
  end

  @doc "Whether the scheduler's last tick is older than `max_age_seconds`, or has never ticked at all."
  def stale?(scheduler_name, max_age_seconds) do
    case last_tick(scheduler_name) do
      :never -> true
      {:ok, last} -> DateTime.diff(DateTime.utc_now(), last) > max_age_seconds
    end
  end

  @doc "Records a malware-scanner adapter failure (e.g. ClamAV unavailable) — called from `MalwareScanner.scan/1` itself, not its callers, so every adapter is covered without touching call sites. Never raises: this sits directly in the KYC upload path, and a Store hiccup must not block or crash a real upload."
  def record_scanner_failure(reason) do
    now = System.system_time(:second)
    key = {:scanner_failure, System.unique_integer([:positive, :monotonic])}
    :ets.insert(Store.table(), {key, now, reason})
    :ets.insert(Store.table(), {:scanner_failure_last_at, now})
    :ok
  rescue
    error -> log_write_failure("record_scanner_failure", error)
  catch
    kind, reason -> log_write_failure("record_scanner_failure", {kind, reason})
  end

  @doc "Count of scanner failures recorded within the last `window_seconds` (default 1 hour)."
  def recent_scanner_failure_count(window_seconds \\ 3600) do
    cutoff = System.system_time(:second) - window_seconds

    ms = [
      {{{:scanner_failure, :_}, :"$1", :_}, [{:>, :"$1", {:const, cutoff}}], [true]}
    ]

    :ets.select_count(Store.table(), ms)
  end

  @doc "The most recent scanner failure's timestamp, regardless of window — a count alone can't distinguish 'failed once an hour ago' from 'still failing right now'."
  def last_scanner_failure_at do
    case :ets.lookup(Store.table(), :scanner_failure_last_at) do
      [{_key, timestamp}] -> {:ok, DateTime.from_unix!(timestamp)}
      [] -> :never
    end
  end

  @doc "Records a backup run failure — called from BackupScheduler on any failure mode of Backup.run/1, unlike ArrearsScheduler/KycRetentionScheduler this scheduler wraps its work in rescue/catch specifically so this always fires. Never raises, same reasoning as record_scanner_failure/1."
  def record_backup_failure(reason) do
    now = System.system_time(:second)
    key = {:backup_failure, System.unique_integer([:positive, :monotonic])}
    :ets.insert(Store.table(), {key, now, reason})
    :ets.insert(Store.table(), {:backup_failure_last_at, now})
    :ok
  rescue
    error -> log_write_failure("record_backup_failure", error)
  catch
    kind, reason -> log_write_failure("record_backup_failure", {kind, reason})
  end

  @doc "Count of backup failures recorded within the last `window_seconds` (default 24 hours — backups run daily, so a 1-hour window like the scanner's would almost always read zero)."
  def recent_backup_failure_count(window_seconds \\ 86_400) do
    cutoff = System.system_time(:second) - window_seconds

    ms = [
      {{{:backup_failure, :_}, :"$1", :_}, [{:>, :"$1", {:const, cutoff}}], [true]}
    ]

    :ets.select_count(Store.table(), ms)
  end

  @doc "The most recent backup failure's timestamp, regardless of window."
  def last_backup_failure_at do
    case :ets.lookup(Store.table(), :backup_failure_last_at) do
      [{_key, timestamp}] -> {:ok, DateTime.from_unix!(timestamp)}
      [] -> :never
    end
  end

  @doc "Free bytes on the filesystem backing `path`, via `df`. Returns `{:error, :path_not_found}` for a directory that doesn't exist yet rather than shelling out to a nonexistent path."
  def disk_free_bytes(path) do
    if File.dir?(path) do
      parse_df(System.cmd("df", ["-Pk", path]))
    else
      {:error, :path_not_found}
    end
  rescue
    _ -> {:error, :df_failed}
  end

  defp parse_df({output, 0}) do
    output
    |> String.trim()
    |> String.split("\n")
    |> List.last()
    |> String.split(~r/\s+/)
    |> case do
      [_filesystem, _blocks, _used, available_kb | _rest] ->
        {:ok, String.to_integer(available_kb) * 1024}

      _ ->
        {:error, :unexpected_output}
    end
  end

  defp parse_df({_output, _status}), do: {:error, :df_failed}

  @doc "Attaches this module's telemetry handlers. Called once from Application.start/2, after the supervision tree (including Monitoring.Store) is already up."
  def attach_telemetry_handlers do
    :telemetry.attach(
      "miway-credit-core-monitoring-repo-query",
      @repo_query_event,
      &__MODULE__.handle_repo_query/4,
      nil
    )

    :telemetry.attach(
      "miway-credit-core-monitoring-error-rendered",
      @error_rendered_event,
      &__MODULE__.handle_error_rendered/4,
      nil
    )
  end

  @doc false
  def handle_error_rendered(_event_name, _measurements, metadata, _config) do
    ErrorReporter.report(metadata.kind, metadata.reason, metadata.stacktrace, metadata)
  rescue
    error -> Logger.error("Monitoring error-rendered telemetry handler failed: #{inspect(error)}")
  catch
    kind, reason ->
      Logger.error(
        "Monitoring error-rendered telemetry handler failed: #{kind} #{inspect(reason)}"
      )
  end

  @doc false
  def handle_repo_query(_event_name, measurements, _metadata, _config) do
    case Map.get(measurements, :queue_time) do
      nil ->
        :ok

      queue_time_native ->
        record_query_sample(System.convert_time_unit(queue_time_native, :native, :millisecond))
    end
  rescue
    error -> Logger.error("Monitoring repo-query telemetry handler failed: #{inspect(error)}")
  catch
    kind, reason ->
      Logger.error("Monitoring repo-query telemetry handler failed: #{kind} #{inspect(reason)}")
  end

  @doc "Records one query's queue-time sample (milliseconds), updating the running count/last-window-max. Never raises: called from a telemetry handler that already can't let anything escape, but this stays defensive independently since it's a public function other callers could reach too."
  def record_query_sample(queue_time_ms) do
    :ets.update_counter(Store.table(), {:query_stats, :count}, 1, {{:query_stats, :count}, 0})
    :ets.insert(Store.table(), {{:query_stats, :last_ms}, queue_time_ms})
    ensure_max_window_started()
    update_max_queue_time(queue_time_ms)
    :ok
  rescue
    error -> log_write_failure("record_query_sample", error)
  catch
    kind, reason -> log_write_failure("record_query_sample", {kind, reason})
  end

  @doc """
  Aggregate DB pool queue-time stats. `sample_count`/`last_queue_time_ms`
  are lifetime-since-boot (an ever-growing counter and the single most
  recent sample are both fine to never reset). `max_queue_time_ms` is
  windowed instead — reset by `Store`'s periodic clean cycle
  (`Store.max_queue_time_window_seconds/0`) alongside its scanner-failure
  prune, so a resolved historical spike doesn't sit there looking like
  an ongoing problem forever; `max_queue_time_window_started_at` says
  since when the current max is being measured.
  """
  def pool_stats do
    %{
      sample_count: lookup_query_stat(:count, 0),
      last_queue_time_ms: lookup_query_stat(:last_ms, nil),
      max_queue_time_ms: lookup_query_stat(:max_ms, nil),
      max_queue_time_window_started_at: max_window_started_at(),
      warning_threshold_ms: @pool_queue_time_warning_ms
    }
  end

  @doc "Whether the current windowed max queue time is at or above the warning threshold — the badge shown on /admin/system-health, not itself an alert."
  def pool_healthy? do
    case lookup_query_stat(:max_ms, nil) do
      nil -> true
      max_ms -> max_ms < @pool_queue_time_warning_ms
    end
  end

  defp ensure_max_window_started do
    case :ets.lookup(Store.table(), {:query_stats, :max_window_started_at}) do
      [{_key, _timestamp}] ->
        :ok

      [] ->
        :ets.insert(
          Store.table(),
          {{:query_stats, :max_window_started_at}, System.system_time(:second)}
        )
    end
  end

  defp max_window_started_at do
    case :ets.lookup(Store.table(), {:query_stats, :max_window_started_at}) do
      [{_key, timestamp}] -> {:ok, DateTime.from_unix!(timestamp)}
      [] -> :never
    end
  end

  defp update_max_queue_time(queue_time_ms) do
    case :ets.lookup(Store.table(), {:query_stats, :max_ms}) do
      [{_key, current_max}] when current_max >= queue_time_ms -> :ok
      _ -> :ets.insert(Store.table(), {{:query_stats, :max_ms}, queue_time_ms})
    end
  end

  defp lookup_query_stat(field, default) do
    case :ets.lookup(Store.table(), {:query_stats, field}) do
      [{_key, value}] -> value
      [] -> default
    end
  end

  defp log_write_failure(function_name, error) do
    Logger.error("Monitoring.#{function_name} failed to write, ignoring: #{inspect(error)}")
    :ok
  end
end
