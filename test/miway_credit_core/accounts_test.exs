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
      assert {:ok, %User{} = user, staff_member} = Accounts.register_staff_member(attrs, "loan_officer")
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
      assert uri =~ "MiwayCreditCore"
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
