defmodule MiwayCreditCore.OrganisationsTest do
  use MiwayCreditCore.DataCase, async: true

  import MiwayCreditCore.OrganisationsFixtures
  import MiwayCreditCore.AccountsFixtures

  alias MiwayCreditCore.{Organisations, Accounts, Repo}
  alias MiwayCreditCore.Organisations.{Organisation, OrganisationSettings}
  alias MiwayCreditCore.Accounts.Scope

  describe "create_organisation/1" do
    test "creates an Organisation and its default OrganisationSettings" do
      assert {:ok, %Organisation{} = organisation} =
               Organisations.create_organisation(%{name: "Acme Lending"})

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

  describe "create_branch/2" do
    test "creates a branch under the scope's organisation" do
      organisation = organisation_fixture()
      scope = %Scope{organisation_id: organisation.id}

      assert {:ok, branch} =
               Organisations.create_branch(scope, %{"name" => "HQ", "code" => "HQ1"})

      assert branch.organisation_id == organisation.id
    end

    test "rejects a duplicate code within the same organisation" do
      organisation = organisation_fixture()
      scope = %Scope{organisation_id: organisation.id}
      branch_fixture(organisation, %{code: "DUP"})

      assert {:error, changeset} =
               Organisations.create_branch(scope, %{"name" => "Other", "code" => "DUP"})

      assert errors_on(changeset).organisation_id
    end

    test "requires a concrete organisation scope, not :all" do
      assert_raise ArgumentError, ~r/not :all/, fn ->
        Organisations.create_branch(%Scope{organisation_id: :all}, %{
          "name" => "HQ",
          "code" => "HQ1"
        })
      end
    end
  end

  describe "list_branches/1 and get_branch!/2" do
    test "lists only the scope's organisation's branches, newest-name-first" do
      org_a = organisation_fixture()
      org_b = organisation_fixture()
      branch_a = branch_fixture(org_a, %{name: "Alpha"})
      _branch_b = branch_fixture(org_b, %{name: "Beta"})

      scope_a = %Scope{organisation_id: org_a.id}
      assert [found] = Organisations.list_branches(scope_a)
      assert found.id == branch_a.id
    end

    test "platform-administrator :all scope sees every organisation's branches" do
      org_a = organisation_fixture()
      org_b = organisation_fixture()
      branch_a = branch_fixture(org_a)
      branch_b = branch_fixture(org_b)

      all_scope = %Scope{organisation_id: :all}
      ids = Organisations.list_branches(all_scope) |> Enum.map(& &1.id)
      assert branch_a.id in ids
      assert branch_b.id in ids
    end

    test "get_branch!/2 raises for a different organisation's branch" do
      org_a = organisation_fixture()
      org_b = organisation_fixture()
      branch = branch_fixture(org_a)
      other_scope = %Scope{organisation_id: org_b.id}

      assert_raise Ecto.NoResultsError, fn ->
        Organisations.get_branch!(other_scope, branch.id)
      end
    end
  end

  test "create_department/1 creates a department under an organisation" do
    organisation = organisation_fixture()

    assert {:ok, department} =
             Organisations.create_department(%{organisation_id: organisation.id, name: "Credit"})

    assert department.organisation_id == organisation.id
  end

  describe "add_staff_to_organisation/2 and get_active_membership_for_staff_member/1" do
    test "links a StaffMember to an Organisation" do
      organisation = organisation_fixture()
      staff_member = bare_staff_member_fixture()

      assert {:ok, membership} =
               Organisations.add_staff_to_organisation(staff_member.id, organisation.id)

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
    {:ok, _user, staff_member} =
      valid_user_attrs() |> Accounts.register_staff_member("loan_officer")

    staff_member
  end
end
