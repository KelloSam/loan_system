defmodule MiwayCreditCore.OrganisationsTest do
  use MiwayCreditCore.DataCase, async: true

  import MiwayCreditCore.OrganisationsFixtures
  import MiwayCreditCore.AccountsFixtures

  alias MiwayCreditCore.{Organisations, Accounts, Repo}
  alias MiwayCreditCore.Organisations.{Organisation, OrganisationSettings}

  describe "create_organisation/1" do
    test "creates an Organisation and its default OrganisationSettings" do
      assert {:ok, %Organisation{} = organisation} = Organisations.create_organisation(%{name: "Acme Lending"})
      assert organisation.status == "active"

      settings = Repo.get_by(OrganisationSettings, organisation_id: organisation.id)
      assert settings.currency == "ZMW"
      assert settings.timezone == "Africa/Lusaka"
    end

    test "rejects a duplicate name" do
      organisation_fixture(%{name: "Duplicate Co"})
      assert {:error, changeset} = Organisations.create_organisation(%{name: "Duplicate Co"})
      assert "has already been taken" in errors_on(changeset).name
    end
  end

  test "get_organisation!/1 fetches by id" do
    organisation = organisation_fixture()
    assert Organisations.get_organisation!(organisation.id).id == organisation.id
  end

  describe "create_branch/1" do
    test "creates a branch under an organisation" do
      organisation = organisation_fixture()
      assert {:ok, branch} = Organisations.create_branch(%{organisation_id: organisation.id, name: "HQ", code: "HQ1"})
      assert branch.organisation_id == organisation.id
    end

    test "rejects a duplicate code within the same organisation" do
      organisation = organisation_fixture()
      branch_fixture(organisation, %{code: "DUP"})
      assert {:error, changeset} =
               Organisations.create_branch(%{organisation_id: organisation.id, name: "Other", code: "DUP"})
      assert errors_on(changeset).organisation_id
    end
  end

  test "create_department/1 creates a department under an organisation" do
    organisation = organisation_fixture()
    assert {:ok, department} = Organisations.create_department(%{organisation_id: organisation.id, name: "Credit"})
    assert department.organisation_id == organisation.id
  end

  describe "add_staff_to_organisation/2 and get_active_membership_for_staff_member/1" do
    test "links a StaffMember to an Organisation" do
      organisation = organisation_fixture()
      staff_member = bare_staff_member_fixture()

      assert {:ok, membership} = Organisations.add_staff_to_organisation(staff_member.id, organisation.id)
      assert membership.status == "active"

      found = Organisations.get_active_membership_for_staff_member(staff_member.id)
      assert found.id == membership.id
    end

    test "returns nil when the staff member has no active membership" do
      staff_member = bare_staff_member_fixture()
      assert Organisations.get_active_membership_for_staff_member(staff_member.id) == nil
    end
  end

  test "assign_staff_to_branch/2 links a membership to a branch" do
    organisation = organisation_fixture()
    branch = branch_fixture(organisation)
    staff_member = bare_staff_member_fixture()
    {:ok, membership} = Organisations.add_staff_to_organisation(staff_member.id, organisation.id)

    assert {:ok, assignment} = Organisations.assign_staff_to_branch(membership.id, branch.id)
    assert assignment.branch_id == branch.id
    assert assignment.organisation_membership_id == membership.id
  end

  # Bypasses AccountsFixtures.staff_member_fixture/2, which now also
  # enrolls in its own throwaway organisation — these tests need a
  # StaffMember with precisely zero (or exactly one, caller-added)
  # memberships to make assertions on membership state meaningful.
  defp bare_staff_member_fixture do
    {:ok, _user, staff_member} = valid_user_attrs() |> Accounts.register_staff_member("loan_officer")
    staff_member
  end
end
