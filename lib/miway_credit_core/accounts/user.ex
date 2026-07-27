defmodule MiwayCreditCore.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(active suspended)

  schema "users" do
    field :email, :string
    field :password, :string, virtual: true
    field :password_hash, :string
    field :status, :string, default: "active"
    field :sessions_invalidated_at, :naive_datetime
    field :totp_secret, :string
    field :totp_enabled, :boolean, default: false
    field :failed_attempts, :integer, default: 0
    field :locked_until, :naive_datetime

    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :password])
    |> validate_required([:email, :password])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
    |> validate_password()
    |> unique_constraint(:email)
    |> put_password_hash()
  end

  @doc "Used by the password-reset flow — touches only :password, not :email."
  def password_changeset(user, attrs) do
    user
    |> cast(attrs, [:password])
    |> validate_required([:password])
    |> validate_password()
    |> put_password_hash()
  end

  @doc "Admin-driven suspend/reactivate — touches only :status."
  def status_changeset(user, attrs) do
    user
    |> cast(attrs, [:status])
    |> validate_required([:status])
    |> validate_inclusion(:status, @statuses)
  end

  # Used by the lockout mechanism — no password hashing, no email validation.
  def security_changeset(user, attrs) do
    user
    |> cast(attrs, [:failed_attempts, :locked_until])
  end

  # Used to enable / disable TOTP — only touches 2FA fields.
  def totp_changeset(user, attrs) do
    user
    |> cast(attrs, [:totp_secret, :totp_enabled])
  end

  @doc "Stamps sessions_invalidated_at — used to force-logout every existing session after a password reset."
  def session_changeset(user, attrs) do
    user
    |> cast(attrs, [:sessions_invalidated_at])
  end

  defp validate_password(changeset) do
    changeset
    |> validate_length(:password, min: 12, max: 72, message: "must be at least 12 characters")
    |> validate_format(:password, ~r/[A-Z]/, message: "must contain at least one uppercase letter")
    |> validate_format(:password, ~r/[a-z]/, message: "must contain at least one lowercase letter")
    |> validate_format(:password, ~r/[0-9]/, message: "must contain at least one number")
  end

  defp put_password_hash(%Ecto.Changeset{valid?: true, changes: %{password: password}} = changeset) do
    change(changeset, %{password_hash: Bcrypt.hash_pwd_salt(password)})
  end

  defp put_password_hash(changeset), do: changeset
end
