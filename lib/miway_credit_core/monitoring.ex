defmodule MiwayCreditCore.Monitoring do
  @moduledoc """
  Operational self-checks — runbook §11's "Monitoring" checklist.
  State lives in `MiwayCreditCore.Monitoring.Store`'s public ETS
  table so it survives whatever process wrote it crashing and
  restarting (a scheduler tick, a telemetry handler).
  """

  require Logger

  alias MiwayCreditCore.Monitoring.Store

  @scheduler_names [:arrears_scheduler, :kyc_retention_scheduler]
  @repo_query_event [:miway_credit_core, :repo, :query]

  @doc "The scheduler names this module tracks heartbeats for."
  def scheduler_names, do: @scheduler_names

  @doc "Records a successful tick. Called as the last line of a scheduler's successful `handle_info` body — a tick that raises earlier never reaches this call, which is the staleness signal."
  def record_tick(scheduler_name) when scheduler_name in @scheduler_names do
    :ets.insert(Store.table(), {{:tick, scheduler_name}, System.system_time(:second)})
    :ok
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

  @doc "Records a malware-scanner adapter failure (e.g. ClamAV unavailable) — called from `MalwareScanner.scan/1` itself, not its callers, so every adapter is covered without touching call sites."
  def record_scanner_failure(reason) do
    key = {:scanner_failure, System.unique_integer([:positive, :monotonic])}
    :ets.insert(Store.table(), {key, System.system_time(:second), reason})
    :ok
  end

  @doc "Count of scanner failures recorded within the last `window_seconds` (default 1 hour)."
  def recent_scanner_failure_count(window_seconds \\ 3600) do
    cutoff = System.system_time(:second) - window_seconds

    ms = [
      {{{:scanner_failure, :_}, :"$1", :_}, [{:>, :"$1", {:const, cutoff}}], [true]}
    ]

    :ets.select_count(Store.table(), ms)
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

  @doc "Records one query's queue-time sample (milliseconds), updating the running count/last/max."
  def record_query_sample(queue_time_ms) do
    :ets.update_counter(Store.table(), {:query_stats, :count}, 1, {{:query_stats, :count}, 0})
    :ets.insert(Store.table(), {{:query_stats, :last_ms}, queue_time_ms})
    update_max_queue_time(queue_time_ms)
    :ok
  end

  @doc "Aggregate DB pool queue-time stats observed since the last reset — a spike or a persistently rising max is the earliest signal of pool exhaustion, before /ready itself starts failing."
  def pool_stats do
    %{
      sample_count: lookup_query_stat(:count, 0),
      last_queue_time_ms: lookup_query_stat(:last_ms, nil),
      max_queue_time_ms: lookup_query_stat(:max_ms, nil)
    }
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
end
