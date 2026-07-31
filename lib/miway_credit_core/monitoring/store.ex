defmodule MiwayCreditCore.Monitoring.Store do
  @moduledoc """
  Owns the ETS table backing `MiwayCreditCore.Monitoring` — supervised
  separately from the schedulers/handlers that write to it (mirrors
  `PlugAttack.Storage.Ets`'s precedent) so heartbeat/failure data
  survives *those* processes crashing and restarting. Started as the
  first child in `Application.start/2`, before `Repo`, so the table
  exists before any telemetry handler can possibly fire.

  This survival guarantee does NOT extend to `Store`'s own process:
  ETS tables are owned by the process that created them and are
  destroyed when that owner terminates (no `:heir`/`:give_away` is
  configured — deliberately not worth the added complexity for
  diagnostics-only data). If `Store` itself crashes, the supervisor
  restarts it and `init/1` creates a brand-new, empty table —
  everything recorded is lost, same as a full application restart.
  This is intentional: see `Monitoring`'s moduledoc for why this is
  documented as a runtime indicator, not a permanent record.
  """

  use GenServer

  @table __MODULE__
  @clean_period :timer.minutes(5)
  @scanner_failure_retention_seconds 7 * 24 * 60 * 60

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))
  end

  @doc false
  def table, do: @table

  @doc "How often (seconds) the pool's windowed max queue time resets — see Monitoring.pool_stats/0."
  def max_queue_time_window_seconds, do: div(@clean_period, 1000)

  @doc "Test-only: wipes all recorded state. Tests touching this table must run async: false and reset in setup, since it's process-global for the whole suite."
  def reset!, do: :ets.delete_all_objects(@table)

  @impl true
  def init(:ok) do
    :ets.new(@table, [
      :named_table,
      :set,
      :public,
      write_concurrency: true,
      read_concurrency: true
    ])

    schedule_clean()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:clean, state) do
    prune_stale_scanner_failures()
    reset_pool_max_window()
    schedule_clean()
    {:noreply, state}
  end

  defp prune_stale_scanner_failures do
    cutoff = System.system_time(:second) - @scanner_failure_retention_seconds

    ms = [
      {{{:scanner_failure, :_}, :"$1", :_}, [{:<, :"$1", {:const, cutoff}}], [true]}
    ]

    :ets.select_delete(@table, ms)
  end

  # A resolved historical spike shouldn't sit in Monitoring.pool_stats/0
  # looking like an ongoing problem forever — reset the windowed max
  # (and its window-start marker) on the same cadence as the
  # scanner-failure prune, not the lifetime sample count/last sample.
  defp reset_pool_max_window do
    :ets.delete(@table, {:query_stats, :max_ms})
    :ets.delete(@table, {:query_stats, :max_window_started_at})
  end

  defp schedule_clean, do: Process.send_after(self(), :clean, @clean_period)
end
