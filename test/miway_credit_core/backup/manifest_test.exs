defmodule MiwayCreditCore.Backup.ManifestTest do
  use ExUnit.Case, async: true

  alias MiwayCreditCore.Backup.Manifest

  setup do
    dir = Path.join(System.tmp_dir!(), "manifest_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  describe "checksum_file!/1" do
    test "matches the real sha256sum binary's output", %{dir: dir} do
      path = Path.join(dir, "sample.bin")
      File.write!(path, "hello world")

      assert {output, 0} = System.cmd("sha256sum", [path])
      [expected, _filename] = String.split(output, "  ", parts: 2)

      assert Manifest.checksum_file!(path) == String.trim(expected)
    end
  end

  describe "build/1" do
    test "includes backup_id, created_at, postgres, kyc_archive, and the key fingerprint when given" do
      manifest =
        Manifest.build(%{
          backup_id: "20260731T000000Z",
          postgres: %{filename: "db.dump"},
          kyc_archive: %{filename: "kyc.tar.gz"},
          kyc_encryption_key_fingerprint_sha256: "abc123"
        })

      assert manifest.backup_id == "20260731T000000Z"
      assert manifest.postgres == %{filename: "db.dump"}
      assert manifest.kyc_archive == %{filename: "kyc.tar.gz"}
      assert manifest.kyc_encryption_key_fingerprint_sha256 == "abc123"
      assert {:ok, %DateTime{}, _} = DateTime.from_iso8601(manifest.created_at)
    end

    test "the key fingerprint is nil when not given" do
      manifest = Manifest.build(%{backup_id: "x", postgres: %{}, kyc_archive: %{}})
      assert manifest.kyc_encryption_key_fingerprint_sha256 == nil
    end
  end

  describe "write!/2 and parse_sha256sums/1" do
    test "writes a manifest.json and a SHA256SUMS covering every given file plus the manifest itself",
         %{dir: dir} do
      File.write!(Path.join(dir, "db.dump"), "fake dump contents")
      db_checksum = Manifest.checksum_file!(Path.join(dir, "db.dump"))

      manifest = Manifest.build(%{backup_id: "x", postgres: %{}, kyc_archive: %{}})
      :ok = Manifest.write!(dir, manifest, [{"db.dump", db_checksum}])

      assert File.exists?(Path.join(dir, "manifest.json"))
      assert {:ok, decoded} = Jason.decode(File.read!(Path.join(dir, "manifest.json")))
      assert decoded["backup_id"] == "x"

      pairs = Manifest.parse_sha256sums(File.read!(Path.join(dir, "SHA256SUMS")))
      assert {"db.dump", ^db_checksum} = List.keyfind(pairs, "db.dump", 0)
      assert List.keyfind(pairs, "manifest.json", 0) != nil
    end
  end

  describe "verify_checksums/2" do
    test "returns :ok when every file matches", %{dir: dir} do
      File.write!(Path.join(dir, "a.txt"), "aaa")
      checksum = Manifest.checksum_file!(Path.join(dir, "a.txt"))

      assert Manifest.verify_checksums(dir, [{"a.txt", checksum}]) == :ok
    end

    test "reports :mismatch for a corrupted file and :missing for an absent one", %{dir: dir} do
      File.write!(Path.join(dir, "a.txt"), "aaa")

      assert {:error, mismatches} =
               Manifest.verify_checksums(dir, [
                 {"a.txt", "wrong_checksum"},
                 {"missing.txt", "does_not_matter"}
               ])

      assert {"a.txt", :mismatch} in mismatches
      assert {"missing.txt", :missing} in mismatches
    end
  end
end
