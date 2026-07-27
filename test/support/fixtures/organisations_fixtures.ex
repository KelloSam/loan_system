defmodule MiwayCreditCore.OrganisationsFixtures do
  @moduledoc "Test helpers for creating MiwayCreditCore.Organisations entities."

  alias MiwayCreditCore.Organisations

  def valid_organisation_attrs(attrs \\ %{}) do
    Enum.into(attrs, %{name: "Test Org #{System.unique_integer([:positive])}"})
  end

  def organisation_fixture(attrs \\ %{}) do
    {:ok, organisation} = attrs |> valid_organisation_attrs() |> Organisations.create_organisation()
    organisation
  end

  def branch_fixture(%Organisations.Organisation{} = organisation, attrs \\ %{}) do
    {:ok, branch} =
      attrs
      |> Enum.into(%{
        organisation_id: organisation.id,
        name: "Test Branch #{System.unique_integer([:positive])}",
        code: "BR#{System.unique_integer([:positive])}"
      })
      |> Organisations.create_branch()

    branch
  end

  @doc """
  Creates a StaffMember already a member of the given organisation —
  and only that one. Bypasses AccountsFixtures.staff_member_fixture/2,
  which would otherwise also enroll the staff member in its own
  throwaway organisation, leaving two memberships and an
  indeterminate "active" one.
  """
  def staff_member_in_organisation_fixture(%Organisations.Organisation{} = organisation, role \\ "loan_officer") do
    {:ok, user, staff_member} =
      MiwayCreditCore.AccountsFixtures.valid_user_attrs()
      |> MiwayCreditCore.Accounts.register_staff_member(role)

    {:ok, _membership} = Organisations.add_staff_to_organisation(staff_member.id, organisation.id)
    user
  end
end
