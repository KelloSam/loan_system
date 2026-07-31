defmodule MiwayCreditCore.Backup.Manifest do
  @moduledoc """
  Builds and verifies the `manifest.json` + `SHA256SUMS` pair written
  alongside every backup. `SHA256SUMS` uses the real `sha256sum`
  output format deliberately — an operator can re-verify a copied-off
  backup independently with plain `sha256sum -c SHA256SUMS`, with no
  dependency on this app.
  """

  @doc "The sha256 checksum of a file on disk, hex-encoded — matches sha256sum's own output format."
  def checksum_file!(path) do
    path
    |> File.stream!([], 2_048_000)
    |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
  end

  @doc "Builds the manifest map for one backup. `attrs` supplies :backup_id, :postgres, :kyc_archive, and optionally :kyc_encryption_key_fingerprint_sha256."
  def build(attrs) do
    %{
      backup_id: attrs.backup_id,
      created_at: DateTime.to_iso8601(DateTime.utc_now()),
      postgres: attrs.postgres,
      kyc_archive: attrs.kyc_archive,
      kyc_encryption_key_fingerprint_sha256:
        Map.get(attrs, :kyc_encryption_key_fingerprint_sha256)
    }
  end

  @doc "Writes manifest.json and SHA256SUMS into `dir`. `checksummed_files` is a list of {filename, checksum} pairs to cover — the manifest itself is added automatically."
  def write!(dir, manifest, checksummed_files) do
    manifest_path = Path.join(dir, "manifest.json")
    File.write!(manifest_path, Jason.encode!(manifest, pretty: true))

    all_checksums = checksummed_files ++ [{"manifest.json", checksum_file!(manifest_path)}]

    sums_content =
      Enum.map_join(all_checksums, "", fn {filename, checksum} -> "#{checksum}  #{filename}\n" end)

    File.write!(Path.join(dir, "SHA256SUMS"), sums_content)

    :ok
  end

  @doc "Parses SHA256SUMS content into a list of {filename, checksum} pairs."
  def parse_sha256sums(content) do
    content
    |> String.split("\n", trim: true)
    |> Enum.map(fn line ->
      [checksum, filename] = String.split(line, "  ", parts: 2)
      {filename, checksum}
    end)
  end

  @doc """
  Verifies files under `dir` against `expected` (a list of
  {relative_path, sha256} pairs — from `parse_sha256sums/1` or a
  manifest's own recorded checksums). Returns `:ok` or
  `{:error, [{relative_path, :missing | :mismatch}]}`.
  """
  def verify_checksums(dir, expected) do
    mismatches =
      Enum.reduce(expected, [], fn {relative_path, expected_checksum}, acc ->
        full_path = Path.join(dir, relative_path)

        cond do
          not File.exists?(full_path) -> [{relative_path, :missing} | acc]
          checksum_file!(full_path) != expected_checksum -> [{relative_path, :mismatch} | acc]
          true -> acc
        end
      end)

    if mismatches == [], do: :ok, else: {:error, Enum.reverse(mismatches)}
  end
end
