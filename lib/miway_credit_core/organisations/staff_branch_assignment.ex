defmodule MiwayCreditCore.Organisations.StaffBranchAssignment do
  @moduledoc "Assigns a staff member's organisation membership to a specific Branch."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "staff_branch_assignments" do
    belongs_to :organisation_membership, MiwayCreditCore.Organisations.OrganisationMembership,
      type: :binary_id

    belongs_to :branch, MiwayCreditCore.Organisations.Branch, type: :binary_id

    timestamps()
  end

  def changeset(assignment, attrs) do
    assignment
    |> cast(attrs, [:organisation_membership_id, :branch_id])
    |> validate_required([:organisation_membership_id, :branch_id])
    |> unique_constraint([:organisation_membership_id, :branch_id])
    |> foreign_key_constraint(:organisation_membership_id)
    |> foreign_key_constraint(:branch_id)
  end
end
