defmodule MiwayCreditCore.Customers.DocumentStorage do
  @moduledoc """
  Where KYC document bytes actually live. Local disk today, under
  `priv/kyc_uploads/` — outside `priv/static`, so `Plug.Static` never
  serves it; the only read path is `CustomerController#download_kyc_document`,
  which re-checks scope and permission on every request before calling
  `read/3`. Swap this module's internals for S3 (or anything else)
  later without touching the context or controller — every caller only
  knows `store/3`/`read/3`/`read_path/3`/`delete/3`.

  Bytes are encrypted at rest with AES-256-GCM (Erlang's built-in
  `:crypto`, no dependency) — a stolen disk or backup never yields a
  readable NRC photo or payslip. The on-disk layout is
  `nonce (12 bytes) <> tag (16 bytes) <> ciphertext`, self-describing
  so no extra DB column is needed to decrypt later.
  """

  @nonce_bytes 12
  @tag_bytes 16

  @doc "The configured KYC upload directory root, e.g. for disk-space monitoring."
  def root do
    Application.get_env(
      :miway_credit_core,
      :kyc_upload_dir,
      Path.join(:code.priv_dir(:miway_credit_core), "kyc_uploads")
    )
  end

  @doc "Encrypts and writes the uploaded file under an opaque, server-generated name. Returns {stored_filename, size_bytes} — size_bytes is the original plaintext size, not the on-disk (encrypted) size."
  def store(%Plug.Upload{} = upload, organisation_id, customer_id) do
    plaintext = File.read!(upload.path)
    stored_filename = Ecto.UUID.generate() <> Path.extname(upload.filename)
    dir = customer_dir(organisation_id, customer_id)
    File.mkdir_p!(dir)

    dest = Path.join(dir, stored_filename)
    File.write!(dest, encrypt(plaintext))

    {stored_filename, byte_size(plaintext)}
  end

  @doc "Reads and decrypts a stored file's bytes."
  def read(organisation_id, customer_id, stored_filename) do
    organisation_id
    |> read_path(customer_id, stored_filename)
    |> File.read!()
    |> decrypt()
  end

  @doc "The on-disk path for a stored file — built server-side from opaque ids, never from client input, so it can't be used for path traversal."
  def read_path(organisation_id, customer_id, stored_filename) do
    Path.join(customer_dir(organisation_id, customer_id), stored_filename)
  end

  def delete(organisation_id, customer_id, stored_filename) do
    organisation_id
    |> read_path(customer_id, stored_filename)
    |> File.rm()
  end

  @doc """
  One-time migration helper (see `mix miway_credit_core.encrypt_existing_kyc_files`)
  — encrypts a file already on disk in place. Only ever safe to call
  against a file known to still be in the old plaintext format; every
  normal caller uses `store/3`, which always encrypts on write.
  """
  def encrypt_file_in_place!(path) do
    File.write!(path, path |> File.read!() |> encrypt())
  end

  defp customer_dir(organisation_id, customer_id) do
    Path.join([root(), organisation_id, customer_id])
  end

  defp encrypt(plaintext) do
    nonce = :crypto.strong_rand_bytes(@nonce_bytes)
    {ciphertext, tag} = :crypto.crypto_one_time_aead(:aes_256_gcm, key(), nonce, plaintext, "", true)
    nonce <> tag <> ciphertext
  end

  defp decrypt(<<nonce::binary-size(@nonce_bytes), tag::binary-size(@tag_bytes), ciphertext::binary>>) do
    case :crypto.crypto_one_time_aead(:aes_256_gcm, key(), nonce, ciphertext, "", tag, false) do
      :error -> raise "KYC document failed to decrypt — the file may be corrupted or tampered with"
      plaintext -> plaintext
    end
  end

  defp key do
    :miway_credit_core
    |> Application.fetch_env!(:kyc_encryption_key)
    |> Base.decode64!()
  end
end
