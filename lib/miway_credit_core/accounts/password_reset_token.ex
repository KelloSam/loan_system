defmodule MiwayCreditCore.Accounts.PasswordResetToken do
  @moduledoc """
  A single-use, expiring password-reset token. Only the SHA-256 hash
  of the raw token is ever stored — the raw value exists only in the
  URL sent to the user, never in the database.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "password_reset_tokens" do
    field :token_hash, :string
    field :expires_at, :utc_datetime
    field :used_at, :utc_datetime

    belongs_to :user, MiwayCreditCore.Accounts.User

    timestamps(updated_at: false)
  end

  def changeset(token, attrs) do
    token
    |> cast(attrs, [:user_id, :token_hash, :expires_at])
    |> validate_required([:user_id, :token_hash, :expires_at])
    |> unique_constraint(:token_hash)
    |> foreign_key_constraint(:user_id)
  end

  @doc "Marks a token consumed — enforces single-use."
  def use_changeset(token, used_at) do
    cast(token, %{used_at: used_at}, [:used_at])
  end
end
