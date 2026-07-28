defmodule MiwayCreditCore.Organisations do
  @moduledoc """
  The multi-tenancy boundary: organisations, branches, departments,
  and the staff memberships/branch assignments that scope a
  StaffMember to one (or more) organisations. Foundational — this
  context depends on nothing else; other contexts depend on it.
  """

  alias MiwayCreditCore.Repo

  alias MiwayCreditCore.Organisations.{
    Organisation,
    OrganisationSettings,
    Branch,
    Department,
    OrganisationMembership,
    StaffBranchAssignment
  }

  @doc "Creates an Organisation and its default OrganisationSettings in one transaction."
  def create_organisation(attrs \\ %{}) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert(:organisation, Organisation.changeset(%Organisation{}, attrs))
    |> Ecto.Multi.insert(:settings, fn %{organisation: organisation} ->
      OrganisationSettings.changeset(%OrganisationSettings{}, %{organisation_id: organisation.id})
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{organisation: organisation}} -> {:ok, organisation}
      {:error, _step, changeset, _} -> {:error, changeset}
    end
  end

  def get_organisation!(id), do: Repo.get!(Organisation, id)

  @doc """
  An organisation's settings row (currency, timezone, payment
  allocation order). Every organisation gets one via
  `create_organisation/1` — nil is only possible for data that
  predates that guarantee, so callers should treat it as optional.
  """
  def get_settings(organisation_id) do
    Repo.get_by(OrganisationSettings, organisation_id: organisation_id)
  end

  def create_branch(attrs \\ %{}) do
    %Branch{}
    |> Branch.changeset(attrs)
    |> Repo.insert()
  end

  def create_department(attrs \\ %{}) do
    %Department{}
    |> Department.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Adds a StaffMember to an Organisation. A StaffMember may belong to more than one."
  def add_staff_to_organisation(staff_member_id, organisation_id) do
    %OrganisationMembership{}
    |> OrganisationMembership.changeset(%{staff_member_id: staff_member_id, organisation_id: organisation_id})
    |> Repo.insert()
  end

  @doc """
  Returns the first active OrganisationMembership for a staff member,
  or nil. Staff are expected to have exactly one active membership in
  practice today — multi-org active-context-switching (if a staff
  member has more than one) is out of scope for this pass.
  """
  def get_active_membership_for_staff_member(staff_member_id) do
    Repo.get_by(OrganisationMembership, staff_member_id: staff_member_id, status: "active")
  end

  def assign_staff_to_branch(organisation_membership_id, branch_id) do
    %StaffBranchAssignment{}
    |> StaffBranchAssignment.changeset(%{
      organisation_membership_id: organisation_membership_id,
      branch_id: branch_id
    })
    |> Repo.insert()
  end
end
