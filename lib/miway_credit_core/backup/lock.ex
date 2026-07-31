defmodule MiwayCreditCore.Backup.Lock do
  @moduledoc """
  A local lock file preventing two backup runs (a scheduled tick and a
  manual on-demand run) from clobbering each other. Deliberately a
  plain local file, not part of the pluggable `Destination` — the lock
  is inherently a single-app-server concept even if backups themselves
  eventually go off-site, mirroring the same single-instance assumption
  already documented for `DocumentStorage`.
  """

  @stale_after_ms :timer.hours(6)

  @doc "Attempts to acquire the lock. Returns :ok, or {:error, :backup_in_progress} if a live lock already exists. A lock older than 6h is treated as a crashed prior run and self-heals."
  def acquire do
    path = lock_path()
    File.mkdir_p!(Path.dirname(path))

    case File.open(path, [:write, :exclusive]) do
      {:ok, io} ->
        IO.write(
          io,
          Jason.encode!(%{
            pid: inspect(self()),
            started_at: DateTime.to_iso8601(DateTime.utc_now())
          })
        )

        File.close(io)
        :ok

      {:error, :eexist} ->
        acquire_after_checking_staleness(path)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Releases the lock — safe to call even if it doesn't exist."
  def release do
    File.rm(lock_path())
    :ok
  end

  defp acquire_after_checking_staleness(path) do
    if stale?(path) do
      File.rm(path)
      acquire()
    else
      {:error, :backup_in_progress}
    end
  end

  defp stale?(path) do
    with {:ok, content} <- File.read(path),
         {:ok, %{"started_at" => started_at}} <- Jason.decode(content),
         {:ok, started_at, _offset} <- DateTime.from_iso8601(started_at) do
      DateTime.diff(DateTime.utc_now(), started_at, :millisecond) > @stale_after_ms
    else
      _ -> true
    end
  end

  defp lock_path, do: Path.join(MiwayCreditCore.Backup.Destination.Local.root(), ".backup.lock")
end
