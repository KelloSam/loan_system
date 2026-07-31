defmodule MiwayCreditCore.Backup.DestinationTest do
  # No adapter is configured for :backup_destination anywhere in this
  # app's config, so Destination.adapter/0 always falls back to Local
  # — this file exercises the dispatch and the real filesystem
  # behavior together. Each test uses its own unique backup_id under
  # the shared test-wide tmp root (config/test.exs), so tests stay
  # isolated from each other without mutating global Application
  # config inside an async test (this project's own established
  # precedent: config-swapping is verified live via mix run instead).
  use ExUnit.Case, async: true

  alias MiwayCreditCore.Backup.Destination

  setup do
    backup_id = "test_#{System.unique_integer([:positive, :monotonic])}"
    on_exit(fn -> Destination.delete(backup_id) end)
    %{backup_id: backup_id}
  end

  test "put/3 then fetch/3 round-trips a file's contents", %{backup_id: backup_id} do
    source = Path.join(System.tmp_dir!(), "dest_test_source_#{backup_id}")
    File.write!(source, "some backup bytes")

    assert :ok = Destination.put(backup_id, "db.dump", source)

    dest = Path.join(System.tmp_dir!(), "dest_test_fetched_#{backup_id}")
    assert :ok = Destination.fetch(backup_id, "db.dump", dest)
    assert File.read!(dest) == "some backup bytes"

    File.rm(source)
    File.rm(dest)
  end

  test "list/0 includes a backup_id after put/3, not before", %{backup_id: backup_id} do
    {:ok, before} = Destination.list()
    refute backup_id in before

    source = Path.join(System.tmp_dir!(), "dest_test_list_#{backup_id}")
    File.write!(source, "x")
    Destination.put(backup_id, "db.dump", source)
    File.rm(source)

    assert {:ok, after_list} = Destination.list()
    assert backup_id in after_list
  end

  test "delete/1 removes the backup_id entirely", %{backup_id: backup_id} do
    source = Path.join(System.tmp_dir!(), "dest_test_delete_#{backup_id}")
    File.write!(source, "x")
    Destination.put(backup_id, "db.dump", source)
    File.rm(source)

    assert :ok = Destination.delete(backup_id)
    {:ok, entries} = Destination.list()
    refute backup_id in entries
  end

  test "fetch/3 of a nonexistent file returns an error, not a raise", %{backup_id: backup_id} do
    dest = Path.join(System.tmp_dir!(), "dest_test_missing_#{backup_id}")
    assert {:error, _reason} = Destination.fetch(backup_id, "does-not-exist.dump", dest)
  end
end
