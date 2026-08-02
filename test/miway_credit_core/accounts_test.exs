defmodule MiwayCreditCore.AccountsTest do
  use MiwayCreditCore.DataCase, async: true

  import MiwayCreditCore.CustomersFixtures
  import MiwayCreditCore.AccountsFixtures
  alias MiwayCreditCore.Accounts
  alias MiwayCreditCore.Accounts.User

  describe "create_user/1" do
    test "creates a user with a hashed password and active status" do
      attrs = valid_user_attrs()
      assert {:ok, %User{} = user} = Accounts.create_user(attrs)
      assert user.email == attrs.email
      assert user.password_hash
      assert user.password_hash != attrs.password
      assert user.status == "active"
    end

    test "rejects a duplicate email" do
      attrs = valid_user_attrs()
      assert {:ok, _} = Accounts.create_user(attrs)
      assert {:error, changeset} = Accounts.create_user(attrs)
      assert "has already been taken" in errors_on(changeset).email
    end

    test "rejects a weak password (too short)" do
      attrs = valid_user_attrs(%{password: "Short1"})
      assert {:error, changeset} = Accounts.create_user(attrs)
      assert errors_on(changeset).password
    end

    test "rejects a password with no uppercase/number" do
      attrs = valid_user_attrs(%{password: "alllowercasepassword"})
      assert {:error, changeset} = Accounts.create_user(attrs)
      assert errors_on(changeset).password
    end

    test "rejects a malformed email" do
      attrs = valid_user_attrs(%{email: "not-an-email"})
      assert {:error, changeset} = Accounts.create_user(attrs)
      assert errors_on(changeset).email
    end
  end

  describe "register_staff_member/2" do
    test "creates a User and a StaffMember in one transaction" do
      attrs = valid_user_attrs()

      assert {:ok, %User{} = user, staff_member} =
               Accounts.register_staff_member(attrs, "loan_officer")

      assert staff_member.user_id == user.id
      assert staff_member.role == "loan_officer"
      assert Accounts.get_staff_member(user.id).id == staff_member.id
    end

    test "rejects an invalid role" do
      attrs = valid_user_attrs()
      assert {:error, changeset} = Accounts.register_staff_member(attrs, "superuser")
      assert errors_on(changeset).role
    end

    test "get_staff_member/1 returns nil for a login with no StaffMember" do
      user = user_fixture()
      assert Accounts.get_staff_member(user.id) == nil
    end
  end

  describe "register_customer_user/2" do
    test "creates a User and links it to an existing Customer" do
      customer = customer_fixture()
      attrs = valid_user_attrs()

      assert {:ok, %User{} = user, customer_user} =
               Accounts.register_customer_user(attrs, customer.id)

      assert customer_user.user_id == user.id
      assert customer_user.customer_id == customer.id

      fetched = Accounts.get_customer_user(user.id)
      assert fetched.customer.id == customer.id
    end

    test "get_customer_user/1 returns nil for a login with no CustomerUser" do
      user = user_fixture()
      assert Accounts.get_customer_user(user.id) == nil
    end
  end

  describe "update_user_status/2" do
    test "suspends and reactivates a user" do
      user = user_fixture()
      assert {:ok, suspended} = Accounts.update_user_status(user, "suspended")
      assert suspended.status == "suspended"

      assert {:ok, reactivated} = Accounts.update_user_status(suspended, "active")
      assert reactivated.status == "active"
    end

    test "rejects an invalid status" do
      user = user_fixture()
      assert {:error, changeset} = Accounts.update_user_status(user, "banned")
      assert errors_on(changeset).status
    end
  end

  describe "get_user_by_email/1 and get_user!/1" do
    test "finds an existing user by email, nil for unknown" do
      user = user_fixture()
      assert Accounts.get_user_by_email(user.email).id == user.id
      assert Accounts.get_user_by_email("nobody@example.com") == nil
    end

    test "get_user!/1 raises for an unknown id" do
      assert_raise Ecto.NoResultsError, fn -> Accounts.get_user!(-1) end
    end
  end

  describe "authenticate_user/2" do
    test "succeeds with correct credentials" do
      user = user_fixture(%{password: "CorrectHorse123"})
      assert {:ok, authenticated} = Accounts.authenticate_user(user.email, "CorrectHorse123")
      assert authenticated.id == user.id
    end

    test "fails for an unknown email without leaking which part was wrong" do
      assert {:error, :invalid_credentials} =
               Accounts.authenticate_user("nobody@example.com", "whatever123A")
    end

    test "fails for a wrong password and increments failed_attempts" do
      user = user_fixture(%{password: "CorrectHorse123"})

      assert {:error, :invalid_credentials} =
               Accounts.authenticate_user(user.email, "WrongPassword1")

      reloaded = Accounts.get_user!(user.id)
      assert reloaded.failed_attempts == 1
    end

    test "resets failed_attempts after a successful login" do
      user = user_fixture(%{password: "CorrectHorse123"})
      Accounts.authenticate_user(user.email, "wrong-one-1")
      Accounts.authenticate_user(user.email, "wrong-two-2")

      assert {:ok, _} = Accounts.authenticate_user(user.email, "CorrectHorse123")
      reloaded = Accounts.get_user!(user.id)
      assert reloaded.failed_attempts == 0
      assert reloaded.locked_until == nil
    end

    test "locks the account after 5 failed attempts, blocking even the correct password" do
      user = user_fixture(%{password: "CorrectHorse123"})

      for _ <- 1..5 do
        Accounts.authenticate_user(user.email, "WrongPassword1")
      end

      reloaded = Accounts.get_user!(user.id)
      assert reloaded.locked_until != nil

      assert {:error, {:account_locked, _until}} =
               Accounts.authenticate_user(user.email, "CorrectHorse123")
    end
  end

  describe "account_locked?/1, increment_failed_attempts/1, reset_failed_attempts/1 (now public — shared with the TOTP step)" do
    test "account_locked?/1 is false for a fresh user, true once locked_until is in the future" do
      user = user_fixture(%{password: "CorrectHorse123"})
      refute Accounts.account_locked?(user)

      user = %{user | locked_until: NaiveDateTime.utc_now() |> NaiveDateTime.add(60, :second)}
      assert Accounts.account_locked?(user)
    end

    test "increment_failed_attempts/1 locks the account on the 5th call" do
      user = user_fixture(%{password: "CorrectHorse123"})

      user =
        Enum.reduce(1..5, user, fn _, acc ->
          {:ok, updated} = Accounts.increment_failed_attempts(acc)
          updated
        end)

      assert Accounts.account_locked?(user)
    end

    test "reset_failed_attempts/1 clears failed_attempts and locked_until" do
      user = user_fixture(%{password: "CorrectHorse123"})
      {:ok, user} = Accounts.increment_failed_attempts(user)

      {:ok, reset} = Accounts.reset_failed_attempts(user)
      assert reset.failed_attempts == 0
      assert reset.locked_until == nil
    end
  end

  describe "TOTP" do
    test "generate_totp_secret/0 returns a 20-byte binary" do
      secret = Accounts.generate_totp_secret()
      assert is_binary(secret)
      assert byte_size(secret) == 20
    end

    test "totp_uri/2 embeds the user's email and the app name" do
      user = user_fixture(%{email: "totp-user@example.com"})
      secret = Accounts.generate_totp_secret()
      uri = Accounts.totp_uri(user, secret)
      assert uri =~ "totp-user@example.com"
      assert uri =~ "MiwayCreditCore"
    end

    test "enable_totp/2 stores the secret encrypted (current version), not plain base64, and flips totp_enabled" do
      user = user_fixture()
      secret = Accounts.generate_totp_secret()
      assert {:ok, updated} = Accounts.enable_totp(user, secret)
      assert updated.totp_enabled
      assert updated.totp_secret_version == 1
      # The stored value is not the raw base64-encoded secret anymore —
      # decoding it does not yield a 20-byte NimbleTOTP secret directly,
      # it yields the nonce<>tag<>ciphertext blob (12 + 16 + 20 = 48 bytes).
      refute updated.totp_secret == Base.encode64(secret)
      decoded_blob = Base.decode64!(updated.totp_secret)
      assert byte_size(decoded_blob) == 48
      assert byte_size(decoded_blob) != byte_size(secret)
    end

    test "enable_totp/2's stored secret round-trips correctly through valid_totp?/2" do
      user = user_fixture()
      secret = Accounts.generate_totp_secret()
      {:ok, updated} = Accounts.enable_totp(user, secret)

      code = NimbleTOTP.verification_code(secret)
      assert Accounts.valid_totp?(updated, code)
    end

    test "disable_totp/1 clears the secret" do
      user = user_fixture()
      secret = Accounts.generate_totp_secret()
      {:ok, enabled} = Accounts.enable_totp(user, secret)

      assert {:ok, disabled} = Accounts.disable_totp(enabled)
      refute disabled.totp_enabled
      assert disabled.totp_secret == nil
    end

    test "valid_totp?/2 accepts a correct current code and rejects a bogus one" do
      user = user_fixture()
      secret = Accounts.generate_totp_secret()
      {:ok, enabled} = Accounts.enable_totp(user, secret)

      code = NimbleTOTP.verification_code(secret)
      assert Accounts.valid_totp?(enabled, code)
      refute Accounts.valid_totp?(enabled, "000000")
    end

    test "valid_totp?/2 is false when TOTP was never enabled" do
      user = user_fixture()
      refute Accounts.valid_totp?(user, "123456")
    end

    test "valid_totp_for_secret?/2 validates against a raw (not-yet-saved) secret" do
      secret = Accounts.generate_totp_secret()
      code = NimbleTOTP.verification_code(secret)
      assert Accounts.valid_totp_for_secret?(secret, code)
      refute Accounts.valid_totp_for_secret?(secret, "000000")
    end
  end

  describe "TOTP legacy (pre-encryption, totp_secret_version: 0) record handling" do
    defp legacy_totp_user_fixture(secret) do
      user = user_fixture()

      {:ok, legacy_user} =
        user
        |> MiwayCreditCore.Accounts.User.totp_changeset(%{
          totp_secret: Base.encode64(secret),
          totp_secret_version: 0,
          totp_enabled: true
        })
        |> MiwayCreditCore.Repo.update()

      legacy_user
    end

    test "valid_totp?/2 still authenticates a legacy plain-base64 secret" do
      secret = Accounts.generate_totp_secret()
      legacy_user = legacy_totp_user_fixture(secret)

      code = NimbleTOTP.verification_code(secret)
      assert Accounts.valid_totp?(legacy_user, code)
      refute Accounts.valid_totp?(legacy_user, "000000")
    end

    test "migrate_legacy_totp_secret/1 re-encrypts a legacy row without changing the underlying secret" do
      secret = Accounts.generate_totp_secret()
      legacy_user = legacy_totp_user_fixture(secret)
      code = NimbleTOTP.verification_code(secret)

      assert {:ok, migrated} = Accounts.migrate_legacy_totp_secret(legacy_user)
      assert migrated.totp_secret_version == 1
      refute migrated.totp_secret == legacy_user.totp_secret

      # The same code still works after migration — no re-enrollment needed.
      assert Accounts.valid_totp?(migrated, code)
    end

    test "migrate_legacy_totp_secret/1 is a no-op for an already-current-version row" do
      user = user_fixture()
      secret = Accounts.generate_totp_secret()
      {:ok, enabled} = Accounts.enable_totp(user, secret)

      assert {:ok, unchanged} = Accounts.migrate_legacy_totp_secret(enabled)
      assert unchanged.totp_secret == enabled.totp_secret
      assert unchanged.totp_secret_version == enabled.totp_secret_version
    end

    test "migrate_legacy_totp_secret/1 is a no-op for a user with no secret at all" do
      user = user_fixture()
      assert {:ok, unchanged} = Accounts.migrate_legacy_totp_secret(user)
      assert unchanged.totp_secret == nil
    end
  end

  describe "password reset" do
    test "request_password_reset/2 delivers a link for a known email" do
      user = user_fixture()
      assert :ok = Accounts.request_password_reset(user.email, &url_fun/1)
      assert_receive {:password_reset_link, delivered_user, url}
      assert delivered_user.id == user.id
      assert url =~ "https://example.com/password-reset/"
    end

    test "request_password_reset/2 returns :ok and delivers nothing for an unknown email" do
      assert :ok = Accounts.request_password_reset("nobody@example.com", &url_fun/1)
      refute_receive {:password_reset_link, _, _}
    end

    test "get_valid_reset_token/1 finds the token behind the delivered URL" do
      user = user_fixture()
      Accounts.request_password_reset(user.email, &url_fun/1)
      assert_receive {:password_reset_link, _user, url}
      raw_token = url |> String.split("/") |> List.last()

      token = Accounts.get_valid_reset_token(raw_token)
      assert token.user.id == user.id
    end

    test "get_valid_reset_token/1 returns nil for a garbage token" do
      assert Accounts.get_valid_reset_token("not-a-real-token") == nil
    end

    test "get_valid_reset_token/1 returns nil for an expired token" do
      user = user_fixture()
      Accounts.request_password_reset(user.email, &url_fun/1)
      assert_receive {:password_reset_link, _user, url}
      raw_token = url |> String.split("/") |> List.last()

      # Force-expire it directly, same as time simply passing.
      past = DateTime.utc_now() |> DateTime.add(-1, :second) |> DateTime.truncate(:second)

      from(t in MiwayCreditCore.Accounts.PasswordResetToken, where: t.user_id == ^user.id)
      |> MiwayCreditCore.Repo.update_all(set: [expires_at: past])

      assert Accounts.get_valid_reset_token(raw_token) == nil
    end

    test "reset_password/2 sets the new password, consumes the token, and invalidates sessions" do
      user = user_fixture()
      Accounts.request_password_reset(user.email, &url_fun/1)
      assert_receive {:password_reset_link, _user, url}
      raw_token = url |> String.split("/") |> List.last()
      token = Accounts.get_valid_reset_token(raw_token)

      assert {:ok, updated} = Accounts.reset_password(token, %{password: "BrandNewPassword1"})
      assert updated.sessions_invalidated_at != nil
      assert {:ok, _} = Accounts.authenticate_user(user.email, "BrandNewPassword1")

      # The token is single-use — it can't be fetched (and therefore not reused) a second time.
      assert Accounts.get_valid_reset_token(raw_token) == nil
    end

    test "reset_password/2 rejects a weak new password" do
      user = user_fixture()
      Accounts.request_password_reset(user.email, &url_fun/1)
      assert_receive {:password_reset_link, _user, url}
      raw_token = url |> String.split("/") |> List.last()
      token = Accounts.get_valid_reset_token(raw_token)

      assert {:error, changeset} = Accounts.reset_password(token, %{password: "short"})
      assert errors_on(changeset).password
    end
  end

  defp url_fun(raw_token), do: "https://example.com/password-reset/#{raw_token}"
end
