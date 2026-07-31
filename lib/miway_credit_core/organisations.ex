defmodule MiwayCreditCore.Organisations do
  @moduledoc """
  The multi-tenancy boundary: organisations, branches, departments,
  and the staff memberships/branch assignments that scope a
  StaffMember to one (or more) organisations. Foundational — this
  context depends on nothing else; other contexts depend on it.
  """

  import Ecto.Query
  alias MiwayCreditCore.Repo
  alias MiwayCreditCore.Accounts.Scope

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

  @doc "All branches for the caller's organisation, newest-name-first — includes inactive ones (an admin needs to see one to reactivate it)."
  def list_branches(%Scope{} = scope) do
    Branch
    |> scope_organisation(scope)
    |> order_by([b], asc: b.name)
    |> Repo.all()
  end

  def get_branch!(%Scope{} = scope, id) do
    Branch
    |> scope_organisation(scope)
    |> Repo.get!(id)
  end

  def create_branch(%Scope{organisation_id: organisation_id}, _attrs)
      when organisation_id == :all do
    raise ArgumentError, "create_branch/2 requires a concrete organisation scope, not :all"
  end

  def create_branch(%Scope{organisation_id: organisation_id}, attrs) do
    # attrs may be atom-keyed (internal/fixture callers) or string-keyed
    # (form params) — normalize before merging so cast/3 never sees a
    # map with mixed key types.
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)

    %Branch{}
    |> Branch.changeset(Map.put(attrs, "organisation_id", organisation_id))
    |> Repo.insert()
  end

  def update_branch(%Branch{} = branch, attrs) do
    branch
    |> Branch.changeset(attrs)
    |> Repo.update()
  end

  def create_department(attrs \\ %{}) do
    %Department{}
    |> Department.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Adds a StaffMember to an Organisation. A StaffMember may belong to more than one."
  def add_staff_to_organisation(staff_member_id, organisation_id) do
    %OrganisationMembership{}
    |> OrganisationMembership.changeset(%{
      staff_member_id: staff_member_id,
      organisation_id: organisation_id
    })
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

  defp scope_organisation(query, %Scope{organisation_id: :all}), do: query

  defp scope_organisation(query, %Scope{organisation_id: organisation_id}) do
    where(query, organisation_id: ^organisation_id)
  end
end
