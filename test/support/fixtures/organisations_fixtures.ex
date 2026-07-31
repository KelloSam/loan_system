defmodule MiwayCreditCore.OrganisationsFixtures do
  @moduledoc "Test helpers for creating MiwayCreditCore.Organisations entities."

  alias MiwayCreditCore.{Organisations, Authorization}
  alias MiwayCreditCore.Accounts.Scope

  def valid_organisation_attrs(attrs \\ %{}) do
    Enum.into(attrs, %{name: "Test Org #{System.unique_integer([:positive])}"})
  end

  @doc "Creates an Organisation with its default Roles already seeded (via Authorization.provision_organisation/1)."
  def organisation_fixture(attrs \\ %{}) do
    {:ok, organisation} =
      attrs |> valid_organisation_attrs() |> Authorization.provision_organisation()

    organisation
  end

  def branch_fixture(%Organisations.Organisation{} = organisation, attrs \\ %{}) do
    scope = %Scope{organisation_id: organisation.id}

    {:ok, branch} =
      attrs
      |> Enum.into(%{
        name: "Test Branch #{System.unique_integer([:positive])}",
        code: "BR#{System.unique_integer([:positive])}"
      })
      |> then(&Organisations.create_branch(scope, &1))

    branch
  end

  @doc """
  Creates a StaffMember already a member of the given organisation —
  and only that one — with the RoleAssignment matching their role
  already granted. Bypasses AccountsFixtures.staff_member_fixture/2,
  which would otherwise also enroll the staff member in its own
  throwaway organisation, leaving two memberships and an
  indeterminate "active" one.
  """
  def staff_member_in_organisation_fixture(
        %Organisations.Organisation{} = organisation,
        role \\ "loan_officer"
      ) do
    {:ok, user, staff_member} =
      MiwayCreditCore.AccountsFixtures.valid_user_attrs()
      |> MiwayCreditCore.Accounts.register_staff_member(role)

    {:ok, _membership} = Authorization.enroll_staff_member(staff_member, organisation.id)
    user
  end
end
