defmodule MiwayCreditCore.Customers.DocumentStorageTest do
  use ExUnit.Case, async: true

  alias MiwayCreditCore.Customers.DocumentStorage

  defp upload(content) do
    path = Path.join(System.tmp_dir!(), "doc_storage_test_#{System.unique_integer([:positive])}")
    File.write!(path, content)
    %Plug.Upload{path: path, filename: "test.txt", content_type: "text/plain"}
  end

  test "store/3 then read/3 round-trips the original bytes" do
    organisation_id = Ecto.UUID.generate()
    customer_id = Ecto.UUID.generate()
    plaintext = "this is real KYC content, not to be stored in the clear"

    {stored_filename, size_bytes} =
      DocumentStorage.store(upload(plaintext), organisation_id, customer_id)

    assert size_bytes == byte_size(plaintext)

    assert DocumentStorage.read(organisation_id, customer_id, stored_filename) == plaintext
  end

  test "the on-disk bytes are not the plaintext — encryption actually happened" do
    organisation_id = Ecto.UUID.generate()
    customer_id = Ecto.UUID.generate()
    plaintext = "sensitive NRC photo bytes go here"

    {stored_filename, _size} =
      DocumentStorage.store(upload(plaintext), organisation_id, customer_id)

    on_disk =
      organisation_id |> DocumentStorage.read_path(customer_id, stored_filename) |> File.read!()

    refute on_disk == plaintext
    assert byte_size(on_disk) > byte_size(plaintext)
  end

  test "a tampered file fails to decrypt instead of silently returning corrupted content" do
    organisation_id = Ecto.UUID.generate()
    customer_id = Ecto.UUID.generate()

    {stored_filename, _size} =
      DocumentStorage.store(upload("original content"), organisation_id, customer_id)

    path = DocumentStorage.read_path(organisation_id, customer_id, stored_filename)

    tampered = path |> File.read!() |> flip_last_byte()
    File.write!(path, tampered)

    assert_raise RuntimeError, ~r/failed to decrypt/, fn ->
      DocumentStorage.read(organisation_id, customer_id, stored_filename)
    end
  end

  defp flip_last_byte(binary) do
    size = byte_size(binary) - 1
    <<prefix::binary-size(size), last>> = binary
    <<prefix::binary, Bitwise.bxor(last, 0xFF)>>
  end
end
