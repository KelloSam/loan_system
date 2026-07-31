defmodule MiwayCreditCore.Backup do
  @moduledoc """
  Runbook §10 — backup automation and restore verification. Orchestrates
  `Backup.Manifest`, `Backup.Destination`, and `Backup.Lock`; the actual
  `pg_dump`/`tar` pipeline (`run/1`) and the restore drill
  (`run_restore_drill/1`) are added in later commits.
  """

  alias MiwayCreditCore.Backup.Destination

  @default_retention_count 14

  @doc "Every backup_id currently at the destination, newest first (backup_ids are sortable UTC timestamps)."
  def list_backups do
    case Destination.list() do
      {:ok, backup_ids} -> {:ok, Enum.sort(backup_ids, :desc)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Deletes every backup beyond the newest `keep` (default: config :miway_credit_core, :backup_retention_count, or 14)."
  def prune_old_backups(keep \\ retention_count()) do
    case list_backups() do
      {:ok, backup_ids} ->
        backup_ids
        |> Enum.drop(keep)
        |> Enum.each(&Destination.delete/1)

        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp retention_count do
    Application.get_env(:miway_credit_core, :backup_retention_count, @default_retention_count)
  end
end
