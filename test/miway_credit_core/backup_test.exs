defmodule MiwayCreditCore.BackupTest do
  # list_backups/0 and prune_old_backups/1 see the whole shared
  # Destination.Local root, not just this test's own entries —
  # async: false so no other test's backup_ids interleave with the
  # counts/ordering these tests assert on.
  use ExUnit.Case, async: false

  alias MiwayCreditCore.Backup
  alias MiwayCreditCore.Backup.Destination

  defp put_fake_backup(backup_id) do
    source = Path.join(System.tmp_dir!(), "backup_test_source_#{backup_id}")
    File.write!(source, "fake")
    :ok = Destination.put(backup_id, "db.dump", source)
    File.rm(source)
  end

  test "list_backups/0 returns backup_ids newest first" do
    put_fake_backup("20260101T000000Z")
    put_fake_backup("20260301T000000Z")
    put_fake_backup("20260201T000000Z")

    {:ok, ids} = Backup.list_backups()
    ours = Enum.filter(ids, &String.starts_with?(&1, "2026"))

    assert ours == ["20260301T000000Z", "20260201T000000Z", "20260101T000000Z"]

    Enum.each(ours, &Destination.delete/1)
  end

  test "prune_old_backups/1 keeps only the newest `keep` and deletes the rest" do
    ids = for n <- 1..5, do: "20260100T00000#{n}Z"
    Enum.each(ids, &put_fake_backup/1)

    assert :ok = Backup.prune_old_backups(2)

    {:ok, remaining} = Backup.list_backups()
    ours = Enum.filter(remaining, &String.starts_with?(&1, "20260100"))

    assert ours == ["20260100T000005Z", "20260100T000004Z"]

    Enum.each(ours, &Destination.delete/1)
  end
end
