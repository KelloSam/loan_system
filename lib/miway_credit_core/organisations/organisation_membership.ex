defmodule MiwayCreditCore.Organisations.OrganisationMembership do
  @moduledoc """
  Links a StaffMember to an Organisation. A real join, not a bare
  organisation_id FK on StaffMember, so a staff member can belong to
  more than one organisation — even though today's common case is
  exactly one.

  platform_administrator StaffMembers deliberately have no membership
  row: platform scope is implied by the role itself (see
  MiwayCreditCore.Accounts.Scope).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(active inactive)

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "organisation_memberships" do
    field :status, :string, default: "active"

    belongs_to :staff_member, MiwayCreditCore.Accounts.StaffMember, type: :binary_id
    belongs_to :organisation, MiwayCreditCore.Organisations.Organisation, type: :binary_id

    timestamps()
  end

  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:staff_member_id, :organisation_id, :status])
    |> validate_required([:staff_member_id, :organisation_id, :status])
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint([:staff_member_id, :organisation_id])
    |> foreign_key_constraint(:staff_member_id)
    |> foreign_key_constraint(:organisation_id)
  end
end
