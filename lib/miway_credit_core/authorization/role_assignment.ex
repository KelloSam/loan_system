defmodule MiwayCreditCore.Authorization.RoleAssignment do
  @moduledoc """
  Grants a Role to an OrganisationMembership. One table covers three
  shapes of the same underlying concept, distinguished by which
  optional fields are set:

    - a permanent "home" role: branch_id nil, expires_at nil
    - a branch-scoped assignment: branch_id set
    - a temporary delegation: expires_at set (and typically
      delegated_from_membership_id, recording whose authority is
      being lent — e.g. covering for someone on leave)

  Branch-scoping is stored here but not yet enforced in queries — no
  business record carries branch_id yet (see
  docs/architecture/context_boundaries.md / the Step 6 plan). What IS
  enforced: does this membership hold this permission at all, within
  its organisation.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "role_assignments" do
    field :expires_at, :utc_datetime

    belongs_to :organisation_membership, MiwayCreditCore.Organisations.OrganisationMembership,
      type: :binary_id

    belongs_to :role, MiwayCreditCore.Authorization.Role, type: :binary_id
    belongs_to :branch, MiwayCreditCore.Organisations.Branch, type: :binary_id

    belongs_to :delegated_from_membership, MiwayCreditCore.Organisations.OrganisationMembership,
      type: :binary_id

    belongs_to :granted_by, MiwayCreditCore.Accounts.User

    timestamps()
  end

  def changeset(role_assignment, attrs) do
    role_assignment
    |> cast(attrs, [
      :organisation_membership_id,
      :role_id,
      :branch_id,
      :expires_at,
      :delegated_from_membership_id,
      :granted_by_id
    ])
    |> validate_required([:organisation_membership_id, :role_id])
    |> foreign_key_constraint(:organisation_membership_id)
    |> foreign_key_constraint(:role_id)
    |> foreign_key_constraint(:branch_id)
    |> foreign_key_constraint(:delegated_from_membership_id)
    |> foreign_key_constraint(:granted_by_id)
  end

  @doc "True when this assignment currently grants its role — either permanent or an unexpired delegation."
  def active?(%__MODULE__{expires_at: nil}), do: true

  def active?(%__MODULE__{expires_at: expires_at}),
    do: DateTime.compare(DateTime.utc_now(), expires_at) == :lt
end
