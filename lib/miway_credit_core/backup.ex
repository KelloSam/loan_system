defmodule MiwayCreditCore.Backup do
  @moduledoc """
  Runbook §10 — backup automation and restore verification. Orchestrates
  `Backup.Manifest`, `Backup.Destination`, and `Backup.Lock`. The
  restore drill (`run_restore_drill/1`) lands in a later commit.
  """

  require Logger

  alias MiwayCreditCore.Backup.{Destination, Lock, Manifest, RepoConfig}
  alias MiwayCreditCore.Customers.DocumentStorage
  alias MiwayCreditCore.Repo

  @default_retention_count 14

  # Not every table — a curated set worth capturing row counts for
  # in the manifest and later checking a restore against.
  @key_tables ~w(customers loan_accounts loan_applications kyc_documents payment_transactions users staff_members)

  @doc """
  Runs a full backup: pg_dump, tar the KYC directory, write the
  manifest+checksums, push everything to the configured Destination,
  then prune old backups. Guarded by Backup.Lock so a scheduled tick
  and a manual run can never clobber each other.
  """
  def run(_opts \\ []) do
    case Lock.acquire() do
      :ok ->
        try do
          do_run()
        after
          Lock.release()
        end

      {:error, :backup_in_progress} = error ->
        error
    end
  end

  @doc "Every backup_id currently at the destination, newest first (backup_ids are sortable UTC timestamps)."
  def list_backups do
    case Destination.list() do
      {:ok, backup_ids} -> {:ok, Enum.sort(backup_ids, :desc)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Summary of the most recent backup (backup_id, created_at, total size), or :unavailable if none exists or it can't be read. Never raises — called from SystemHealthController."
  def latest_backup_info do
    case list_backups() do
      {:ok, [latest | _]} -> fetch_manifest_summary(latest)
      {:ok, []} -> :unavailable
      {:error, _reason} -> :unavailable
    end
  rescue
    _ -> :unavailable
  catch
    _, _ -> :unavailable
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

  defp fetch_manifest_summary(backup_id) do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "miway_credit_core_manifest_fetch_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)
    tmp_path = Path.join(tmp_dir, "manifest.json")

    try do
      with :ok <- Destination.fetch(backup_id, "manifest.json", tmp_path),
           {:ok, content} <- File.read(tmp_path),
           {:ok, manifest} <- Jason.decode(content, keys: :atoms) do
        %{
          backup_id: manifest.backup_id,
          created_at: manifest.created_at,
          size_bytes: manifest.postgres.size_bytes + manifest.kyc_archive.size_bytes
        }
      else
        _ -> :unavailable
      end
    after
      File.rm_rf(tmp_dir)
    end
  end

  defp do_run do
    backup_id = generate_backup_id()
    tmp_dir = Path.join(System.tmp_dir!(), "miway_credit_core_backup_#{backup_id}")
    File.mkdir_p!(tmp_dir)

    try do
      with {:ok, postgres_info} <- dump_postgres(tmp_dir),
           {:ok, kyc_info} <- archive_kyc(tmp_dir),
           :ok <- write_manifest(tmp_dir, backup_id, postgres_info, kyc_info),
           :ok <- push_to_destination(tmp_dir, backup_id) do
        prune_old_backups()
        {:ok, backup_id}
      end
    after
      File.rm_rf(tmp_dir)
    end
  end

  defp generate_backup_id, do: Calendar.strftime(DateTime.utc_now(), "%Y%m%dT%H%M%SZ")

  defp dump_postgres(tmp_dir) do
    params = RepoConfig.connection_params()
    dump_path = Path.join(tmp_dir, "db.dump")

    args = [
      "-h",
      params.hostname,
      "-p",
      to_string(params.port),
      "-U",
      params.username,
      "--format=custom",
      "--no-password",
      "--file=#{dump_path}",
      params.database
    ]

    case System.cmd("pg_dump", args,
           env: [{"PGPASSWORD", params.password}],
           stderr_to_stdout: true
         ) do
      {_output, 0} ->
        {:ok,
         %{
           filename: "db.dump",
           sha256: Manifest.checksum_file!(dump_path),
           size_bytes: File.stat!(dump_path).size,
           table_row_counts: table_row_counts(),
           canary: canary_record()
         }}

      {output, _status} ->
        Logger.error("Backup: pg_dump failed: #{output}")
        {:error, :pg_dump_failed}
    end
  end

  defp table_row_counts do
    Map.new(@key_tables, fn table ->
      %{rows: [[count]]} = Repo.query!("SELECT count(*) FROM \"#{table}\"")
      {table, count}
    end)
  end

  # The most recently inserted KYC document — a concrete known record
  # the restore drill can assert survived, not just a row count.
  defp canary_record do
    case Repo.query("SELECT id::text FROM kyc_documents ORDER BY inserted_at DESC LIMIT 1") do
      {:ok, %{rows: [[id]]}} -> %{table: "kyc_documents", id: id}
      _ -> nil
    end
  end

  defp archive_kyc(tmp_dir) do
    kyc_root = DocumentStorage.root()
    File.mkdir_p!(kyc_root)
    archive_path = Path.join(tmp_dir, "kyc.tar.gz")

    args = ["-czf", archive_path, "-C", Path.dirname(kyc_root), Path.basename(kyc_root)]

    case System.cmd("tar", args, stderr_to_stdout: true) do
      {_output, 0} ->
        {:ok,
         %{
           filename: "kyc.tar.gz",
           sha256: Manifest.checksum_file!(archive_path),
           size_bytes: File.stat!(archive_path).size,
           files: kyc_file_checksums(kyc_root)
         }}

      {output, _status} ->
        Logger.error("Backup: tar failed: #{output}")
        {:error, :tar_failed}
    end
  end

  defp kyc_file_checksums(kyc_root) do
    if File.dir?(kyc_root) do
      kyc_root
      |> list_files_recursive()
      |> Enum.map(fn path ->
        %{path: Path.relative_to(path, kyc_root), sha256: Manifest.checksum_file!(path)}
      end)
    else
      []
    end
  end

  defp list_files_recursive(dir) do
    dir
    |> File.ls!()
    |> Enum.flat_map(fn entry ->
      path = Path.join(dir, entry)
      if File.dir?(path), do: list_files_recursive(path), else: [path]
    end)
  end

  defp write_manifest(tmp_dir, backup_id, postgres_info, kyc_info) do
    manifest =
      Manifest.build(%{
        backup_id: backup_id,
        postgres: postgres_info,
        kyc_archive: kyc_info,
        kyc_encryption_key_fingerprint_sha256: key_fingerprint()
      })

    Manifest.write!(tmp_dir, manifest, [
      {"db.dump", postgres_info.sha256},
      {"kyc.tar.gz", kyc_info.sha256}
    ])
  end

  # A non-reversible fingerprint only — never the key itself. Safe to
  # store alongside ciphertext (same trust model as a password hash);
  # lets an operator confirm which key generation a backup was
  # encrypted under without ever exposing it.
  defp key_fingerprint do
    case Application.get_env(:miway_credit_core, :kyc_encryption_key) do
      nil ->
        nil

      key ->
        key
        |> Base.decode64!()
        |> then(&:crypto.hash(:sha256, &1))
        |> Base.encode16(case: :lower)
    end
  end

  defp push_to_destination(tmp_dir, backup_id) do
    Enum.reduce_while(["db.dump", "kyc.tar.gz", "manifest.json", "SHA256SUMS"], :ok, fn filename,
                                                                                        :ok ->
      case Destination.put(backup_id, filename, Path.join(tmp_dir, filename)) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:destination_put_failed, filename, reason}}}
      end
    end)
  end
end
