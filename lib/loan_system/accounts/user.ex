defmodule LoanSystem.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :email, :string
    field :password, :string, virtual: true
    field :password_hash, :string
    field :role, :string, default: "client"  # can be "client" or "admin"

    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :password])
    |> validate_required([:email, :password])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
    |> validate_length(:password, min: 8, max: 72)
    |> unique_constraint(:email)
    |> put_password_hash()
  end

  # Separate changeset for admin-only role assignment
  def admin_changeset(user, attrs) do
    user
    |> changeset(attrs)
    |> cast(attrs, [:role])
    |> validate_inclusion(:role, ["admin", "client"])
  end

  defp put_password_hash(%Ecto.Changeset{valid?: true, changes: %{password: password}} = changeset) do
    password_hash = Bcrypt.hash_pwd_salt(password)
    change(changeset, %{password_hash: password_hash})
  end

  defp put_password_hash(changeset), do: changeset
end
