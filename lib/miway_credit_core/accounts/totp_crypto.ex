defmodule MiwayCreditCore.Accounts.TotpCrypto do
  @moduledoc """
  AES-256-GCM encryption for TOTP secrets at rest (Erlang's built-in
  `:crypto`, no dependency) — a stolen database copy alone can no
  longer be decoded into working MFA seeds. Mirrors
  `MiwayCreditCore.Customers.DocumentStorage`'s KYC file encryption
  (same nonce/tag/ciphertext layout), but reads a dedicated
  `MFA_ENCRYPTION_KEY` — deliberately never the same key as
  `:kyc_encryption_key` — so compromising one secret domain never
  exposes the other.

  The on-disk/DB layout is `nonce (12 bytes) <> tag (16 bytes) <>
  ciphertext`, self-describing, Base64-encoded for storage in the
  `users.totp_secret` string column. `users.totp_secret_version`
  records whether a given row holds this format (`>= 1`) or predates
  it (`0`/legacy plaintext-Base64) — see `Accounts.valid_totp?/2` and
  `Accounts.migrate_legacy_totp_secret/1`. The version number also
  doubles as future key-rotation metadata: a later rotation would
  introduce version 2 (re-encrypted under a new key) without breaking
  the ability to still read version-1 rows during the rotation window.
  """

  @nonce_bytes 12
  @tag_bytes 16

  @doc "Encrypts a raw TOTP secret, returning the nonce<>tag<>ciphertext blob."
  def encrypt(plaintext) when is_binary(plaintext) do
    nonce = :crypto.strong_rand_bytes(@nonce_bytes)

    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(:aes_256_gcm, key(), nonce, plaintext, "", true)

    nonce <> tag <> ciphertext
  end

  @doc "Decrypts a nonce<>tag<>ciphertext blob, raising on tamper or corruption."
  def decrypt(
        <<nonce::binary-size(@nonce_bytes), tag::binary-size(@tag_bytes), ciphertext::binary>>
      ) do
    case :crypto.crypto_one_time_aead(:aes_256_gcm, key(), nonce, ciphertext, "", tag, false) do
      :error ->
        raise "TOTP secret failed to decrypt — it may be corrupted or tampered with"

      plaintext ->
        plaintext
    end
  end

  defp key do
    :miway_credit_core
    |> Application.fetch_env!(:mfa_encryption_key)
    |> Base.decode64!()
  end
end
