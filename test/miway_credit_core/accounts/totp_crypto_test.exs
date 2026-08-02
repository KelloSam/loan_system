defmodule MiwayCreditCore.Accounts.TotpCryptoTest do
  use ExUnit.Case, async: true

  alias MiwayCreditCore.Accounts.TotpCrypto

  describe "encrypt/1 and decrypt/1" do
    test "round-trips a raw TOTP secret exactly" do
      secret = NimbleTOTP.secret()
      blob = TotpCrypto.encrypt(secret)
      assert TotpCrypto.decrypt(blob) == secret
    end

    test "produces a different blob each time (random nonce), even for the same secret" do
      secret = NimbleTOTP.secret()
      assert TotpCrypto.encrypt(secret) != TotpCrypto.encrypt(secret)
    end

    test "the stored blob does not embed the raw secret in any recognizable form" do
      secret = NimbleTOTP.secret()
      blob = TotpCrypto.encrypt(secret)
      refute blob =~ secret
      refute Base.encode64(blob) =~ Base.encode64(secret)
    end

    test "raises on a tampered ciphertext" do
      secret = NimbleTOTP.secret()

      <<nonce::binary-size(12), tag::binary-size(16), ciphertext::binary>> =
        TotpCrypto.encrypt(secret)

      <<first_byte, rest::binary>> = ciphertext
      tampered_ciphertext = <<Bitwise.bxor(first_byte, 0xFF), rest::binary>>

      assert_raise RuntimeError, ~r/failed to decrypt/, fn ->
        TotpCrypto.decrypt(nonce <> tag <> tampered_ciphertext)
      end
    end

    test "raises on a tampered authentication tag" do
      secret = NimbleTOTP.secret()

      <<nonce::binary-size(12), _tag::binary-size(16), ciphertext::binary>> =
        TotpCrypto.encrypt(secret)

      bogus_tag = :crypto.strong_rand_bytes(16)

      assert_raise RuntimeError, ~r/failed to decrypt/, fn ->
        TotpCrypto.decrypt(nonce <> bogus_tag <> ciphertext)
      end
    end

    test "raises on a tampered nonce (authentication fails even though nonce isn't secret)" do
      secret = NimbleTOTP.secret()

      <<_nonce::binary-size(12), tag::binary-size(16), ciphertext::binary>> =
        TotpCrypto.encrypt(secret)

      bogus_nonce = :crypto.strong_rand_bytes(12)

      assert_raise RuntimeError, ~r/failed to decrypt/, fn ->
        TotpCrypto.decrypt(bogus_nonce <> tag <> ciphertext)
      end
    end
  end
end
