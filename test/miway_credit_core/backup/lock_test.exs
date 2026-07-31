defmodule MiwayCreditCore.Backup.LockTest do
  # The lock is a single file shared by the whole app (not per-backup-id)
  # — async: false, with a release in setup so no test leaks a held
  # lock into the next one.
  use ExUnit.Case, async: false

  alias MiwayCreditCore.Backup.{Destination, Lock}

  setup do
    Lock.release()
    :ok
  end

  test "acquire/0 succeeds, then a second acquire/0 fails while the first is held" do
    assert Lock.acquire() == :ok
    assert Lock.acquire() == {:error, :backup_in_progress}
  end

  test "release/0 lets a subsequent acquire/0 succeed again" do
    assert Lock.acquire() == :ok
    assert Lock.release() == :ok
    assert Lock.acquire() == :ok
  end

  test "release/0 is safe to call when no lock is held" do
    assert Lock.release() == :ok
  end

  test "a stale lock (older than 6h) self-heals instead of blocking forever" do
    lock_path = Path.join(Destination.Local.root(), ".backup.lock")
    File.mkdir_p!(Path.dirname(lock_path))

    stale_started_at = DateTime.utc_now() |> DateTime.add(-7, :hour) |> DateTime.to_iso8601()
    File.write!(lock_path, Jason.encode!(%{pid: "stale", started_at: stale_started_at}))

    assert Lock.acquire() == :ok
  end

  test "a fresh lock (under 6h) is not treated as stale" do
    lock_path = Path.join(Destination.Local.root(), ".backup.lock")
    File.mkdir_p!(Path.dirname(lock_path))

    fresh_started_at = DateTime.utc_now() |> DateTime.add(-1, :hour) |> DateTime.to_iso8601()
    File.write!(lock_path, Jason.encode!(%{pid: "fresh", started_at: fresh_started_at}))

    assert Lock.acquire() == {:error, :backup_in_progress}
  end
end
