defmodule Mix.Tasks.MiwayCreditCore.Backup do
  @moduledoc """
  Runs a backup now — the same pipeline `BackupScheduler` runs
  automatically. Useful for an ad-hoc backup before a risky operation.

      mix miway_credit_core.backup
  """

  use Mix.Task

  alias MiwayCreditCore.Backup

  @shortdoc "Runs a backup now"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    case Backup.run() do
      {:ok, backup_id} ->
        Mix.shell().info("Backup complete: #{backup_id}")

      {:error, :backup_in_progress} ->
        Mix.shell().error("A backup is already in progress.")
        System.halt(1)

      {:error, reason} ->
        Mix.shell().error("Backup failed: #{inspect(reason)}")
        System.halt(1)
    end
  end
end
