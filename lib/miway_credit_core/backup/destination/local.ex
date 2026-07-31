defmodule MiwayCreditCore.Backup.Destination.Local do
  @moduledoc """
  Writes backup files under a configured local directory
  (`config :miway_credit_core, :backup_root_dir`) — one subdirectory
  per `backup_id`. The only `Destination` adapter built; a real
  off-site target is a deploy-time addition.
  """

  @behaviour MiwayCreditCore.Backup.Destination

  @doc "The configured backup root directory."
  def root do
    Application.get_env(
      :miway_credit_core,
      :backup_root_dir,
      Path.join(:code.priv_dir(:miway_credit_core), "backups")
    )
  end

  @impl true
  def put(backup_id, filename, local_path) do
    dest_dir = backup_dir(backup_id)
    File.mkdir_p!(dest_dir)
    File.cp(local_path, Path.join(dest_dir, filename))
  end

  @impl true
  def fetch(backup_id, filename, dest_path) do
    File.cp(Path.join(backup_dir(backup_id), filename), dest_path)
  end

  @impl true
  def list do
    case File.ls(root()) do
      {:ok, entries} -> {:ok, Enum.sort(entries)}
      {:error, :enoent} -> {:ok, []}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def delete(backup_id) do
    case File.rm_rf(backup_dir(backup_id)) do
      {:ok, _deleted} -> :ok
      {:error, reason, _file} -> {:error, reason}
    end
  end

  defp backup_dir(backup_id), do: Path.join(root(), backup_id)
end
