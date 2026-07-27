defmodule MiwayCreditCore.Accounts.StaffMember do
  @moduledoc """
  The employee identity attached to a login `User`. A 1:1 relationship
  — one User is at most one StaffMember.

  `role` has no organisation scoping yet (no `organisation_id`):
  Organisations is a reserved context (Step 5, see
  `docs/architecture/context_boundaries.md`) that doesn't exist yet.
  The `organisation_administrator` role value exists without real
  org-scoped permissions behind it — fine-grained authorization is
  explicitly deferred, only identity is being fixed in this pass.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @roles ~w(platform_administrator organisation_administrator loan_officer)

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "staff_members" do
    field :role, :string

    belongs_to :user, MiwayCreditCore.Accounts.User

    timestamps()
  end

  def changeset(staff_member, attrs) do
    staff_member
    |> cast(attrs, [:user_id, :role])
    |> validate_required([:user_id, :role])
    |> validate_inclusion(:role, @roles)
    |> unique_constraint(:user_id)
    |> foreign_key_constraint(:user_id)
  end
end
