defmodule MiwayCreditCore.Monitoring.Store do
  @moduledoc """
  Owns the public ETS table backing `MiwayCreditCore.Monitoring` —
  supervised separately from the schedulers/handlers that write to it
  (mirrors `PlugAttack.Storage.Ets`'s precedent) so heartbeat/failure
  data survives a scheduler crash-and-restart instead of resetting
  along with it. Started as the first child in `Application.start/2`,
  before `Repo`, so the table exists before any telemetry handler can
  possibly fire.
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

  defp schedule_clean, do: Process.send_after(self(), :clean, @clean_period)
end
