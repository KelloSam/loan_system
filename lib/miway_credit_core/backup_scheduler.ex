defmodule MiwayCreditCore.BackupScheduler do
  @moduledoc """
  Periodically runs MiwayCreditCore.Backup.run/1. Its own GenServer,
  same reasoning as KycRetentionScheduler's own moduledoc — different
  domain, different cadence (daily), different risk profile.

  Disabled in the test environment (config :miway_credit_core,
  __MODULE__, enabled: false) — Backup.run/1 is exercised directly by
  its own tests against the real test DB instead.

  Unlike ArrearsScheduler/KycRetentionScheduler, this scheduler
  deliberately wraps its work in rescue/catch rather than letting an
  exception crash the process. Those two schedulers rely on a missing
  heartbeat as the only failure signal, on purpose — but a backup
  failure needs to be positively observable (Monitoring.record_backup_failure/1),
  not just inferred from staleness, and only reaching the rescue clause
  guarantees that call happens on every failure mode, not just ones
  that happen to leave the process alive.
  """

  use GenServer
  require Logger

  alias MiwayCreditCore.{Backup, Monitoring}

  @default_interval_ms :timer.hours(24)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Process.send_after(self(), :run_backup, :timer.minutes(1))
    {:ok, %{interval_ms: interval_ms()}}
  end

  @impl true
  def handle_info(:run_backup, state) do
    case Backup.run() do
      {:ok, backup_id} ->
        Logger.info("BackupScheduler: completed #{backup_id}")
        Monitoring.record_tick(:backup_scheduler)

      {:error, :backup_in_progress} ->
        Logger.info("BackupScheduler: skipped tick — a backup is already in progress")

      {:error, reason} ->
        Logger.error("BackupScheduler: backup failed: #{inspect(reason)}")
        Monitoring.record_backup_failure(reason)
    end

    {:noreply, state}
  rescue
    error ->
      Logger.error("BackupScheduler: backup raised: #{inspect(error)}")
      Monitoring.record_backup_failure(error)
      {:noreply, state}
  catch
    kind, reason ->
      Logger.error("BackupScheduler: backup #{kind}: #{inspect(reason)}")
      Monitoring.record_backup_failure({kind, reason})
      {:noreply, state}
  after
    Process.send_after(self(), :run_backup, state.interval_ms)
  end

  defp interval_ms do
    Application.get_env(:miway_credit_core, __MODULE__, [])
    |> Keyword.get(:interval_ms, @default_interval_ms)
  end
end
