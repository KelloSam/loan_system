defmodule MiwayCreditCore.Accounts do
  alias MiwayCreditCore.Repo
  alias MiwayCreditCore.Accounts.{User, StaffMember, CustomerUser}

  def create_user(attrs \\ %{}) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  def get_user_by_email(email), do: Repo.get_by(User, email: email)

  def get_user!(id), do: Repo.get!(User, id)

  @doc """
  Creates a login User and its StaffMember record (employee identity)
  in one transaction, so a User is never left without a role attached.
  """
  def register_staff_member(user_attrs, role) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert(:user, User.changeset(%User{}, user_attrs))
    |> Ecto.Multi.insert(:staff_member, fn %{user: user} ->
      StaffMember.changeset(%StaffMember{}, %{user_id: user.id, role: role})
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user, staff_member: staff_member}} -> {:ok, user, staff_member}
      {:error, _step, changeset, _} -> {:error, changeset}
    end
  end

  @doc """
  Creates a login User and links it to an existing Customer via
  CustomerUser (the customer-portal identity) in one transaction.
  """
  def register_customer_user(user_attrs, customer_id) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert(:user, User.changeset(%User{}, user_attrs))
    |> Ecto.Multi.insert(:customer_user, fn %{user: user} ->
      CustomerUser.changeset(%CustomerUser{}, %{user_id: user.id, customer_id: customer_id})
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user, customer_user: customer_user}} -> {:ok, user, customer_user}
      {:error, _step, changeset, _} -> {:error, changeset}
    end
  end

  @doc "Returns the StaffMember for a user id, or nil if this login isn't staff."
  def get_staff_member(user_id), do: Repo.get_by(StaffMember, user_id: user_id)

  @doc "Returns the CustomerUser (with :customer preloaded) for a user id, or nil."
  def get_customer_user(user_id) do
    CustomerUser
    |> Repo.get_by(user_id: user_id)
    |> Repo.preload(:customer)
  end

  @doc "Admin-driven suspend/reactivate. Suspended users are logged out on their next request."
  def update_user_status(%User{} = user, status) do
    user
    |> User.status_changeset(%{status: status})
    |> Repo.update()
  end

  # ---------------------------------------------------------------------------
  # Authentication with lockout protection
  # ---------------------------------------------------------------------------

  @max_attempts 5
  @lockout_minutes 15

  @doc """
  Authenticates a user by email and password.

  Returns:
    {:ok, user}                          — credentials valid
    {:error, :invalid_credentials}       — wrong password (attempts incremented)
    {:error, {:account_locked, until}}   — account is temporarily locked
  """
  def authenticate_user(email, password) do
    user = get_user_by_email(email)

    case user do
      nil ->
        Bcrypt.no_user_verify()
        {:error, :invalid_credentials}

      user ->
        cond do
          account_locked?(user) ->
            {:error, {:account_locked, user.locked_until}}

          Bcrypt.verify_pass(password, user.password_hash) ->
            reset_failed_attempts(user)
            {:ok, user}

          true ->
            increment_failed_attempts(user)
            {:error, :invalid_credentials}
        end
    end
  end

  defp account_locked?(%User{locked_until: nil}), do: false

  defp account_locked?(%User{locked_until: locked_until}) do
    NaiveDateTime.compare(NaiveDateTime.utc_now(), locked_until) == :lt
  end

  defp increment_failed_attempts(user) do
    new_attempts = (user.failed_attempts || 0) + 1

    attrs =
      if new_attempts >= @max_attempts do
        locked_until =
          NaiveDateTime.utc_now()
          |> NaiveDateTime.add(@lockout_minutes * 60, :second)
          |> NaiveDateTime.truncate(:second)

        %{failed_attempts: new_attempts, locked_until: locked_until}
      else
        %{failed_attempts: new_attempts}
      end

    user |> User.security_changeset(attrs) |> Repo.update()
  end

  defp reset_failed_attempts(%User{failed_attempts: 0, locked_until: nil}), do: :ok

  defp reset_failed_attempts(user) do
    user
    |> User.security_changeset(%{failed_attempts: 0, locked_until: nil})
    |> Repo.update()
  end

  # ---------------------------------------------------------------------------
  # Two-factor authentication (TOTP)
  # ---------------------------------------------------------------------------

  @doc "Generates a fresh 20-byte TOTP secret."
  def generate_totp_secret, do: NimbleTOTP.secret()

  @doc """
  Returns the otpauth:// URI for the given user and secret.
  This URI is encoded as a QR code for the user to scan with their
  authenticator app.
  """
  def totp_uri(%User{email: email}, secret) do
    NimbleTOTP.otpauth_uri("MiwayCreditCore:#{email}", secret, issuer: "MiwayCreditCore")
  end

  @doc """
  Returns true if the 6-digit TOTP code matches the user's stored secret.
  The secret is stored base64-encoded in the DB; this function decodes it
  before passing to NimbleTOTP.
  """
  def valid_totp?(%User{totp_secret: encoded}, code) when is_binary(encoded) do
    secret = Base.decode64!(encoded)
    NimbleTOTP.valid?(secret, code)
  end

  def valid_totp?(_, _), do: false

  @doc "Validates a raw binary secret against a code (used during the enable flow)."
  def valid_totp_for_secret?(secret, code) when is_binary(secret) do
    NimbleTOTP.valid?(secret, code)
  end

  @doc "Enables TOTP for a user, persisting the base64-encoded secret."
  def enable_totp(%User{} = user, secret) when is_binary(secret) do
    user
    |> User.totp_changeset(%{totp_secret: Base.encode64(secret), totp_enabled: true})
    |> Repo.update()
  end

  @doc "Disables TOTP and clears the stored secret."
  def disable_totp(%User{} = user) do
    user
    |> User.totp_changeset(%{totp_secret: nil, totp_enabled: false})
    |> Repo.update()
  end
end
