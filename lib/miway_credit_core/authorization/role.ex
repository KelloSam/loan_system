defmodule MiwayCreditCore.Authorization.Role do
  @moduledoc """
  A named permission bundle within an Organisation. `name` is drawn
  from the same fixed vocabulary as StaffMember.role — not free-text —
  since there's no "create a custom role" flow to justify open naming
  yet. What's configurable per organisation is which permissions each
  named role actually grants (see RolePermission), not the name itself.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @names ~w(platform_administrator organisation_administrator loan_officer)

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "roles" do
    field :name, :string
    field :description, :string

    belongs_to :organisation, MiwayCreditCore.Organisations.Organisation, type: :binary_id

    timestamps()
  end

  def changeset(role, attrs) do
    role
    |> cast(attrs, [:organisation_id, :name, :description])
    |> validate_required([:organisation_id, :name])
    |> validate_inclusion(:name, @names)
    |> unique_constraint([:organisation_id, :name])
    |> foreign_key_constraint(:organisation_id)
  end
end
