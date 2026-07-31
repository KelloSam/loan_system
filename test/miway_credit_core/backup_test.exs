defmodule MiwayCreditCore.BackupTest do
  # list_backups/0 and prune_old_backups/1 see the whole shared
  # Destination.Local root, not just this test's own entries —
  # async: false so no other test's backup_ids interleave with the
  # counts/ordering these tests assert on. DataCase (not plain
  # ExUnit.Case) because run/1's table_row_counts/canary_record call
  # Repo.query! directly, which needs this test process to hold a
  # checked-out sandbox connection (Sandbox.mode is :manual). Note
  # this only covers those in-BEAM queries — the real pg_dump/tar
  # calls below are separate OS processes and see only what's
  # actually committed to the real test DB, never this test's own
  # uncommitted sandboxed rows.
  use MiwayCreditCore.DataCase, async: false

  alias MiwayCreditCore.Backup
  alias MiwayCreditCore.Backup.{Destination, Manifest}

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

  describe "run/1 (real pg_dump/tar against the real test DB and KYC dir)" do
    test "produces a backup with verifiable checksums and the expected manifest shape" do
      assert {:ok, backup_id} = Backup.run()

      on_exit(fn -> Destination.delete(backup_id) end)

      dest_dir = Path.join(Destination.Local.root(), backup_id)
      assert File.exists?(Path.join(dest_dir, "db.dump"))
      assert File.exists?(Path.join(dest_dir, "kyc.tar.gz"))

      manifest = Jason.decode!(File.read!(Path.join(dest_dir, "manifest.json")), keys: :atoms)
      assert manifest.backup_id == backup_id
      assert Map.has_key?(manifest.postgres.table_row_counts, :customers)
      assert Map.has_key?(manifest.postgres.table_row_counts, :kyc_documents)

      sums = Manifest.parse_sha256sums(File.read!(Path.join(dest_dir, "SHA256SUMS")))
      assert Manifest.verify_checksums(dest_dir, sums) == :ok
    end

    test "a second run while the first holds the lock is refused" do
      assert :ok = MiwayCreditCore.Backup.Lock.acquire()

      on_exit(fn -> MiwayCreditCore.Backup.Lock.release() end)

      assert Backup.run() == {:error, :backup_in_progress}
    end

    test "latest_backup_info/0 reflects the most recent successful run" do
      assert {:ok, backup_id} = Backup.run()
      on_exit(fn -> Destination.delete(backup_id) end)

      assert %{backup_id: ^backup_id, size_bytes: size_bytes, created_at: created_at} =
               Backup.latest_backup_info()

      assert size_bytes > 0
      assert {:ok, %DateTime{}, _} = DateTime.from_iso8601(created_at)
    end
  end

  describe "run_restore_drill/1 (real CREATE/DROP DATABASE + pg_restore against a scratch DB)" do
    test "restores a real backup and verifies it, cleaning up the scratch DB and dir on success" do
      assert {:ok, backup_id} = Backup.run()
      on_exit(fn -> Destination.delete(backup_id) end)

      assert {:ok, report} = Backup.run_restore_drill(backup_id)

      assert report.overall_status == "ok"
      assert report.backup_id_restored == backup_id
      assert report.postgres_restore.status == "ok"
      assert report.postgres_restore.canary_found? == true
      assert report.kyc_restore.status == "ok"
      assert report.kyc_restore.files_mismatched == 0

      {:ok, scratch_db} = Backup.scratch_database_name()
      refute scratch_db in list_real_databases()
    end

    test "a backup_id that doesn't exist fails cleanly with a diagnostic report, not a raise" do
      assert {:error, report} = Backup.run_restore_drill("this-backup-id-does-not-exist")

      assert report.overall_status == "failed"
      assert report.backup_id_restored == "this-backup-id-does-not-exist"
      assert is_binary(report.reason)
    end
  end

  # Deliberately doesn't test the ":latest, no backups at all" path
  # automatically — the only way to exercise it would be mutating the
  # shared :backup_root_dir Application config mid-suite, the exact
  # class of shared-global-state risk this project's own tests already
  # avoid elsewhere (config-swapping is verified live via mix run
  # instead — confirmed manually working, see the commit message).

  defp list_real_databases do
    params = MiwayCreditCore.Backup.RepoConfig.connection_params()

    {output, 0} =
      System.cmd(
        "psql",
        [
          "-h",
          params.hostname,
          "-p",
          to_string(params.port),
          "-U",
          params.username,
          "--no-password",
          "-d",
          "postgres",
          "-t",
          "-c",
          "SELECT datname FROM pg_database;"
        ],
        env: [{"PGPASSWORD", params.password}]
      )

    output |> String.split("\n") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
  end

  describe "latest_backup_info/0 when the newest backup_id has no manifest" do
    test "returns :unavailable instead of raising" do
      # A "9..." prefix sorts after any realistic UTC-timestamp backup_id
      # (which all start with "2..."), guaranteeing this is the newest
      # entry regardless of what other real backups exist concurrently.
      backup_id = "99999999T999999Z"
      put_fake_backup(backup_id)
      on_exit(fn -> Destination.delete(backup_id) end)

      assert Backup.latest_backup_info() == :unavailable
    end
  end
end
