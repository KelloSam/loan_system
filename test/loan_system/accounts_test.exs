defmodule LoanSystem.AccountsTest do
  use LoanSystem.DataCase, async: true

  import LoanSystem.AccountsFixtures
  alias LoanSystem.Accounts
  alias LoanSystem.Accounts.User

  describe "create_user/1" do
    test "creates a user with a hashed password" do
      attrs = valid_user_attrs()
      assert {:ok, %User{} = user} = Accounts.create_user(attrs)
      assert user.email == attrs.email
      assert user.password_hash
      assert user.password_hash != attrs.password
      assert user.role == "client"
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

  describe "create_user_with_role/1" do
    test "creates an admin user" do
      attrs = valid_user_attrs(%{role: "admin"})
      assert {:ok, %User{role: "admin"}} = Accounts.create_user_with_role(attrs)
    end

    test "rejects an invalid role" do
      attrs = valid_user_attrs(%{role: "superuser"})
      assert {:error, changeset} = Accounts.create_user_with_role(attrs)
      assert errors_on(changeset).role
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
      assert {:error, :invalid_credentials} = Accounts.authenticate_user(user.email, "WrongPassword1")

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
      assert uri =~ "LoanSystem"
    end

    test "enable_totp/2 stores a base64-encoded secret and flips totp_enabled" do
      user = user_fixture()
      secret = Accounts.generate_totp_secret()
      assert {:ok, updated} = Accounts.enable_totp(user, secret)
      assert updated.totp_enabled
      assert updated.totp_secret == Base.encode64(secret)
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
end
