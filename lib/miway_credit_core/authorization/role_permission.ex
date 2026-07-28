defmodule MiwayCreditCore.Authorization.RolePermission do
  @moduledoc "Grants one permission key (from the static catalog — see Authorization.permission_keys/0) to a Role."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "role_permissions" do
    field :permission_key, :string

    belongs_to :role, MiwayCreditCore.Authorization.Role, type: :binary_id

    timestamps(updated_at: false)
  end

  def changeset(role_permission, attrs) do
    role_permission
    |> cast(attrs, [:role_id, :permission_key])
    |> validate_required([:role_id, :permission_key])
    |> validate_inclusion(:permission_key, MiwayCreditCore.Authorization.permission_keys())
    |> unique_constraint([:role_id, :permission_key])
    |> foreign_key_constraint(:role_id)
  end
end
