defmodule MiwayCreditCore.Backup.Destination do
  @moduledoc """
  Swappable-adapter behaviour for where a backup's files actually go —
  same shape as `Accounts.PasswordResetNotifier`/`Customers.MalwareScanner`.
  `Local` (writes under a configured directory) is the only adapter
  built; a real off-site target (S3, rsync to a second host, ...) is a
  deploy-time addition, same treatment as SMTP/ClamAV before it.

  Configured via `config :miway_credit_core, :backup_destination, Adapter`.
  """

  @callback put(backup_id :: String.t(), filename :: String.t(), local_path :: String.t()) ::
              :ok | {:error, term()}
  @callback fetch(backup_id :: String.t(), filename :: String.t(), dest_path :: String.t()) ::
              :ok | {:error, term()}
  @callback list() :: {:ok, [String.t()]} | {:error, term()}
  @callback delete(backup_id :: String.t()) :: :ok | {:error, term()}

  def put(backup_id, filename, local_path), do: adapter().put(backup_id, filename, local_path)
  def fetch(backup_id, filename, dest_path), do: adapter().fetch(backup_id, filename, dest_path)
  def list, do: adapter().list()
  def delete(backup_id), do: adapter().delete(backup_id)

  defp adapter do
    Application.get_env(
      :miway_credit_core,
      :backup_destination,
      MiwayCreditCore.Backup.Destination.Local
    )
  end
end
