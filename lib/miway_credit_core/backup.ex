defmodule MiwayCreditCore.Backup do
  @moduledoc """
  Runbook §10 — backup automation and restore verification. Orchestrates
  `Backup.Manifest`, `Backup.Destination`, and `Backup.Lock`.
  """

  require Logger

  alias MiwayCreditCore.Backup.{Destination, Lock, Manifest, RepoConfig}
  alias MiwayCreditCore.Customers.DocumentStorage
  alias MiwayCreditCore.Repo

  @default_retention_count 14

  # Not every table — a curated set worth capturing row counts for
  # in the manifest and later checking a restore against.
  @key_tables ~w(customers loan_accounts loan_applications kyc_documents payment_transactions users staff_members)

  # Fixed suffix, not a caller-supplied name — there is no parameter
  # through which run_restore_drill/1 could ever be pointed at an
  # arbitrary database. Combined with the recursion guard below, this
  # makes hitting the real database structurally impossible, not just
  # unlikely.
  @restore_drill_suffix "_restore_drill"

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

  @doc """
  Restores `backup_id` (default `:latest`) into a fresh scratch
  database and a fresh scratch KYC directory, then verifies the
  restored data against the backup's own manifest — never against a
  live re-query of the real database. Never touches the real database
  or KYC directory (see `scratch_database_name/0` and the module
  attribute above). Deliberately does not decrypt anything — per-file
  sha256 comparison is a stronger byte-fidelity guarantee than
  decrypt-and-inspect, and keeping `KYC_ENCRYPTION_KEY` out of this
  automated path preserves the whole point of keeping it separate (see
  `mix miway_credit_core.verify_kyc_key` for the key's own, human-gated
  check).

  On success, the scratch database is dropped and the scratch KYC
  directory removed. On any hard failure (pg_restore itself failing,
  the scratch connection failing, tar extraction failing), both are
  left in place for inspection — the returned report names them.

  Returns `{:ok, report}` where `report.overall_status` is `"ok"` or
  `"mismatch"` (ran to completion, but found a real integrity problem
  — still worth surfacing as data, not just an error tuple), or
  `{:error, report}` for a hard failure. `report` is diagnostic-only —
  no SQL text, no customer data, no paths beyond scratch identifiers.
  """
  def run_restore_drill(backup_id \\ :latest) do
    case resolve_backup_id(backup_id) do
      {:ok, resolved_id} ->
        do_restore_drill(resolved_id)

      {:error, reason} ->
        {:error,
         %{
           drill_id: nil,
           backup_id_restored: nil,
           ran_at: DateTime.to_iso8601(DateTime.utc_now()),
           overall_status: "failed",
           reason: inspect(reason)
         }}
    end
  end

  defp resolve_backup_id(:latest) do
    case list_backups() do
      {:ok, [latest | _]} -> {:ok, latest}
      {:ok, []} -> {:error, :no_backups_available}
      {:error, reason} -> {:error, reason}
    end
  end

  defp resolve_backup_id(backup_id) when is_binary(backup_id), do: {:ok, backup_id}

  defp do_restore_drill(backup_id) do
    drill_id = "#{backup_id}_#{System.unique_integer([:positive])}"
    fetch_dir = Path.join(System.tmp_dir!(), "miway_credit_core_drill_fetch_#{drill_id}")

    scratch_kyc_dir =
      Path.join(System.tmp_dir!(), "miway_credit_core_restore_drill_kyc_#{drill_id}")

    File.mkdir_p!(fetch_dir)

    base = %{
      drill_id: drill_id,
      backup_id_restored: backup_id,
      ran_at: DateTime.to_iso8601(DateTime.utc_now())
    }

    case scratch_database_name() do
      {:ok, scratch_db} ->
        run_drill_with_scratch(backup_id, fetch_dir, scratch_kyc_dir, scratch_db, base)

      {:error, reason} ->
        {:error, Map.merge(base, %{overall_status: "failed", reason: inspect(reason)})}
    end
  end

  # scratch_db is resolved (a pure string computation, no I/O) before
  # this runs, so it's known throughout — including in rescue/catch —
  # regardless of which stage below fails. An unexpected exception
  # here (not just an {:error, _} tuple a stage returns cleanly) must
  # never leave the scratch database silently orphaned and unreported;
  # DROP DATABASE IF EXISTS is harmless to attempt even if it was never
  # actually created yet.
  defp run_drill_with_scratch(backup_id, fetch_dir, scratch_kyc_dir, scratch_db, base) do
    try do
      result =
        with {:ok, manifest} <- fetch_and_verify_backup(backup_id, fetch_dir),
             :ok <- recreate_scratch_database(scratch_db),
             :ok <- restore_dump(fetch_dir, scratch_db),
             {:ok, postgres_report} <- verify_postgres(scratch_db, manifest),
             {:ok, kyc_report} <- verify_kyc(fetch_dir, scratch_kyc_dir, manifest) do
          overall =
            if postgres_report.status == "ok" and kyc_report.status == "ok",
              do: "ok",
              else: "mismatch"

          {:ok,
           Map.merge(base, %{
             postgres_restore: postgres_report,
             kyc_restore: kyc_report,
             overall_status: overall
           })}
        end

      case result do
        {:ok, report} ->
          drop_scratch_database(scratch_db)
          File.rm_rf(scratch_kyc_dir)
          {:ok, report}

        {:error, reason} ->
          {:error,
           Map.merge(base, %{
             overall_status: "failed",
             reason: inspect(reason),
             scratch_database_left_for_inspection: scratch_db,
             scratch_kyc_dir_left_for_inspection: scratch_kyc_dir
           })}
      end
    rescue
      error ->
        {:error,
         Map.merge(base, %{
           overall_status: "failed",
           reason: "raised: " <> inspect(error),
           scratch_database_left_for_inspection: scratch_db,
           scratch_kyc_dir_left_for_inspection: scratch_kyc_dir
         })}
    catch
      kind, reason ->
        {:error,
         Map.merge(base, %{
           overall_status: "failed",
           reason: "#{kind}: #{inspect(reason)}",
           scratch_database_left_for_inspection: scratch_db,
           scratch_kyc_dir_left_for_inspection: scratch_kyc_dir
         })}
    after
      File.rm_rf(fetch_dir)
    end
  end

  defp fetch_and_verify_backup(backup_id, fetch_dir) do
    with :ok <- Destination.fetch(backup_id, "db.dump", Path.join(fetch_dir, "db.dump")),
         :ok <- Destination.fetch(backup_id, "kyc.tar.gz", Path.join(fetch_dir, "kyc.tar.gz")),
         :ok <-
           Destination.fetch(backup_id, "manifest.json", Path.join(fetch_dir, "manifest.json")),
         {:ok, content} <- File.read(Path.join(fetch_dir, "manifest.json")),
         {:ok, manifest} <- Jason.decode(content, keys: :atoms),
         :ok <-
           Manifest.verify_checksums(fetch_dir, [
             {"db.dump", manifest.postgres.sha256},
             {"kyc.tar.gz", manifest.kyc_archive.sha256}
           ]) do
      {:ok, manifest}
    else
      {:error, reason} -> {:error, {:fetch_or_verify_failed, reason}}
    end
  end

  @doc false
  def scratch_database_name do
    %{database: real_db} = RepoConfig.connection_params()

    cond do
      String.ends_with?(real_db, @restore_drill_suffix) ->
        {:error, :refusing_recursive_drill}

      true ->
        scratch = real_db <> @restore_drill_suffix
        if scratch == real_db, do: {:error, :scratch_equals_real}, else: {:ok, scratch}
    end
  end

  defp recreate_scratch_database(scratch_db) do
    params = RepoConfig.connection_params()

    with {:ok, _} <- run_psql(params, "DROP DATABASE IF EXISTS \"#{scratch_db}\";"),
         {:ok, _} <- run_psql(params, "CREATE DATABASE \"#{scratch_db}\";") do
      :ok
    else
      {:error, reason} -> {:error, {:scratch_database_setup_failed, reason}}
    end
  end

  defp drop_scratch_database(scratch_db) do
    run_psql(RepoConfig.connection_params(), "DROP DATABASE IF EXISTS \"#{scratch_db}\";")
  end

  defp run_psql(params, sql) do
    args = [
      "-h",
      params.hostname,
      "-p",
      to_string(params.port),
      "-U",
      params.username,
      "--no-password",
      "-d",
      "postgres",
      "-c",
      sql
    ]

    case System.cmd("psql", args, env: [{"PGPASSWORD", params.password}], stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {output, _status} -> {:error, output}
    end
  end

  defp restore_dump(fetch_dir, scratch_db) do
    params = RepoConfig.connection_params()
    dump_path = Path.join(fetch_dir, "db.dump")

    args = [
      "-h",
      params.hostname,
      "-p",
      to_string(params.port),
      "-U",
      params.username,
      "-d",
      scratch_db,
      "--no-owner",
      "--no-privileges",
      "--no-password",
      dump_path
    ]

    case System.cmd("pg_restore", args,
           env: [{"PGPASSWORD", params.password}],
           stderr_to_stdout: true
         ) do
      {_output, 0} -> :ok
      {output, _status} -> {:error, {:pg_restore_failed, output}}
    end
  end

  defp verify_postgres(scratch_db, manifest) do
    params = RepoConfig.connection_params()

    connect_opts = [
      hostname: params.hostname,
      port: params.port,
      username: params.username,
      password: params.password,
      database: scratch_db
    ]

    case Postgrex.start_link(connect_opts) do
      {:ok, conn} ->
        try do
          table_results =
            Map.new(manifest.postgres.table_row_counts, fn {table, expected} ->
              table_name = to_string(table)

              %{rows: [[actual]]} =
                Postgrex.query!(conn, "SELECT count(*) FROM \"#{table_name}\"", [])

              {table_name, %{expected: expected, actual: actual, matches: actual == expected}}
            end)

          all_match? = Enum.all?(table_results, fn {_table, %{matches: matches}} -> matches end)
          canary_found? = canary_found?(conn, manifest.postgres[:canary])

          {:ok,
           %{
             status: if(all_match? and canary_found?, do: "ok", else: "mismatch"),
             table_row_counts: table_results,
             canary_found?: canary_found?
           }}
        after
          GenServer.stop(conn)
        end

      {:error, reason} ->
        {:error, {:postgrex_connect_failed, inspect(reason)}}
    end
  end

  defp canary_found?(_conn, nil), do: true

  # id::text = $1, not id = $1::uuid — casting the parameter (rather
  # than the column) makes a raw Postgrex connection (no Ecto type
  # layer) try to encode the manifest's hyphenated UUID string as raw
  # 16-byte binary and fail; casting the column instead keeps the
  # parameter a plain text comparison, which needs no special encoding.
  defp canary_found?(conn, %{table: "kyc_documents", id: id}) do
    case Postgrex.query(conn, "SELECT 1 FROM kyc_documents WHERE id::text = $1", [id]) do
      {:ok, %{num_rows: n}} -> n > 0
      _ -> false
    end
  end

  defp canary_found?(_conn, _other), do: false

  defp verify_kyc(fetch_dir, scratch_kyc_dir, manifest) do
    File.mkdir_p!(scratch_kyc_dir)
    archive_path = Path.join(fetch_dir, "kyc.tar.gz")

    case System.cmd("tar", ["-xzf", archive_path, "-C", scratch_kyc_dir], stderr_to_stdout: true) do
      {_output, 0} ->
        extracted_root = Path.join(scratch_kyc_dir, Path.basename(DocumentStorage.root()))

        expected =
          Enum.map(manifest.kyc_archive.files, fn %{path: path, sha256: sha} -> {path, sha} end)

        case Manifest.verify_checksums(extracted_root, expected) do
          :ok ->
            {:ok,
             %{
               status: "ok",
               files_checked: length(expected),
               files_matched: length(expected),
               files_mismatched: 0
             }}

          {:error, mismatches} ->
            {:ok,
             %{
               status: "mismatch",
               files_checked: length(expected),
               files_matched: length(expected) - length(mismatches),
               files_mismatched: length(mismatches)
             }}
        end

      {output, _status} ->
        {:error, {:tar_extract_failed, output}}
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
