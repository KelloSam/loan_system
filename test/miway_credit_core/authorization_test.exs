defmodule MiwayCreditCore.AuthorizationTest do
  use MiwayCreditCore.DataCase, async: true

  import MiwayCreditCore.{OrganisationsFixtures, AccountsFixtures, CustomersFixtures, LoansFixtures}

  alias MiwayCreditCore.{Authorization, Accounts, Applications}
  alias MiwayCreditCore.Accounts.Scope

  describe "provision_organisation/1" do
    test "seeds 3 default roles, each with the expected permissions" do
      {:ok, organisation} = Authorization.provision_organisation(%{name: "Acme Lending"})

      platform_admin = Authorization.get_role_by_name(organisation.id, "platform_administrator")
      org_admin = Authorization.get_role_by_name(organisation.id, "organisation_administrator")
      loan_officer = Authorization.get_role_by_name(organisation.id, "loan_officer")

      assert Authorization.permissions_for_role(platform_admin.id) == MapSet.new(Authorization.permission_keys())
      assert Authorization.permissions_for_role(org_admin.id) == MapSet.new(Authorization.permission_keys())

      loan_officer_permissions = Authorization.permissions_for_role(loan_officer.id)
      assert "applications.create" in loan_officer_permissions
      assert "applications.approve" not in loan_officer_permissions
      assert "payments.reverse" not in loan_officer_permissions
      assert "audit.view" not in loan_officer_permissions
    end
  end

  describe "authorized?/2" do
    test "platform administrator (:all scope) is authorized for everything, in any organisation" do
      admin = admin_fixture()
      scope = %Scope{staff_member: Accounts.get_staff_member(admin.id), organisation_id: :all}

      for permission_key <- Authorization.permission_keys() do
        assert Authorization.authorized?(scope, permission_key)
      end
    end

    test "organisation administrator is authorized for everything within their own organisation" do
      organisation = organisation_fixture()
      user = staff_member_in_organisation_fixture(organisation, "organisation_administrator")
      staff_member = Accounts.get_staff_member(user.id)
      scope = %Scope{staff_member: staff_member, organisation_id: organisation.id}

      assert Authorization.authorized?(scope, "applications.approve")
      assert Authorization.authorized?(scope, "payments.reverse")
      assert Authorization.authorized?(scope, "audit.view")
    end

    test "loan officer is denied approve/reject/reverse/audit but granted create/view" do
      organisation = organisation_fixture()
      user = staff_member_in_organisation_fixture(organisation, "loan_officer")
      staff_member = Accounts.get_staff_member(user.id)
      scope = %Scope{staff_member: staff_member, organisation_id: organisation.id}

      assert Authorization.authorized?(scope, "applications.create")
      assert Authorization.authorized?(scope, "applications.view")
      refute Authorization.authorized?(scope, "applications.approve")
      refute Authorization.authorized?(scope, "applications.reject")
      refute Authorization.authorized?(scope, "payments.reverse")
      refute Authorization.authorized?(scope, "audit.view")
    end

    test "a staff member with no RoleAssignment at all is authorized for nothing" do
      organisation = organisation_fixture()
      {:ok, user, staff_member} = valid_user_attrs() |> Accounts.register_staff_member("loan_officer")
      {:ok, _membership} = MiwayCreditCore.Organisations.add_staff_to_organisation(staff_member.id, organisation.id)
      scope = %Scope{staff_member: staff_member, organisation_id: organisation.id}

      refute Authorization.authorized?(scope, "applications.view")
      refute Authorization.authorized?(scope, "applications.create")
    end

    test "a customer scope (no staff_member) is never authorized for anything" do
      customer = customer_fixture()
      scope = %Scope{customer: customer, organisation_id: customer.organisation_id}
      refute Authorization.authorized?(scope, "applications.view")
    end

    test "an expired delegation no longer grants its permissions" do
      organisation = organisation_fixture()
      user = staff_member_in_organisation_fixture(organisation, "loan_officer")
      staff_member = Accounts.get_staff_member(user.id)
      membership = MiwayCreditCore.Organisations.get_active_membership_for_staff_member(staff_member.id)
      scope = %Scope{staff_member: staff_member, organisation_id: organisation.id}

      org_admin_role = Authorization.get_role_by_name(organisation.id, "organisation_administrator")
      past = DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.truncate(:second)

      {:ok, _delegation} = Authorization.assign_role(membership.id, org_admin_role.id, %{expires_at: past})

      # The delegation existed but already expired — still no approve permission.
      refute Authorization.authorized?(scope, "applications.approve")
    end

    test "an active (unexpired) delegation grants its permissions on top of the home role" do
      organisation = organisation_fixture()
      user = staff_member_in_organisation_fixture(organisation, "loan_officer")
      staff_member = Accounts.get_staff_member(user.id)
      membership = MiwayCreditCore.Organisations.get_active_membership_for_staff_member(staff_member.id)
      scope = %Scope{staff_member: staff_member, organisation_id: organisation.id}

      refute Authorization.authorized?(scope, "applications.approve")

      org_admin_role = Authorization.get_role_by_name(organisation.id, "organisation_administrator")
      future = DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second)
      {:ok, _delegation} = Authorization.assign_role(membership.id, org_admin_role.id, %{expires_at: future})

      assert Authorization.authorized?(scope, "applications.approve")
    end
  end

  describe "approval_limit/2 and enforcement in Applications.approve_application/2" do
    test "blocks approval when the requested amount exceeds the approver's limit" do
      organisation = organisation_fixture()
      user = staff_member_in_organisation_fixture(organisation, "organisation_administrator")
      staff_member = Accounts.get_staff_member(user.id)
      role = Authorization.get_role_by_name(organisation.id, "organisation_administrator")
      {:ok, _limit} = Authorization.set_approval_limit(role.id, "applications.approve", Decimal.new("500.00"))

      scope = %Scope{user: user, staff_member: staff_member, organisation_id: organisation.id}
      customer = customer_fixture_in_organisation(organisation)
      application = application_fixture(%{"customer_id" => customer.id, "requested_amount" => "1000.00"})
      {:ok, application} = Applications.assess_application(application, scope)

      assert Authorization.approval_limit(scope, "applications.approve") == Decimal.new("500.00")
      assert {:error, :exceeds_approval_limit} = Applications.approve_application(application, scope, true)
    end

    test "allows approval within the limit" do
      organisation = organisation_fixture()
      user = staff_member_in_organisation_fixture(organisation, "organisation_administrator")
      staff_member = Accounts.get_staff_member(user.id)
      role = Authorization.get_role_by_name(organisation.id, "organisation_administrator")
      {:ok, _limit} = Authorization.set_approval_limit(role.id, "applications.approve", Decimal.new("5000.00"))

      scope = %Scope{user: user, staff_member: staff_member, organisation_id: organisation.id}
      customer = customer_fixture_in_organisation(organisation)
      application = application_fixture(%{"customer_id" => customer.id, "requested_amount" => "1000.00"})
      {:ok, application} = Applications.assess_application(application, scope)

      assert {:ok, _approved} = Applications.approve_application(application, scope, true)
    end

    test "no ApprovalLimit set means unlimited" do
      organisation = organisation_fixture()
      user = staff_member_in_organisation_fixture(organisation, "organisation_administrator")
      staff_member = Accounts.get_staff_member(user.id)
      scope = %Scope{user: user, staff_member: staff_member, organisation_id: organisation.id}

      assert Authorization.approval_limit(scope, "applications.approve") == nil
    end
  end

  describe "maker-checker in Applications.approve_application/2 and reject_application/3" do
    test "the submitter cannot approve their own application" do
      organisation = organisation_fixture()
      user = staff_member_in_organisation_fixture(organisation, "organisation_administrator")
      staff_member = Accounts.get_staff_member(user.id)
      scope = %Scope{user: user, staff_member: staff_member, organisation_id: organisation.id}

      customer = customer_fixture_in_organisation(organisation)
      {:ok, application} =
        Applications.create_application(scope, valid_application_attrs(%{"customer_id" => customer.id}))
      {:ok, application} = Applications.assess_application(application, scope)

      assert {:error, :maker_checker_violation} = Applications.approve_application(application, scope, true)
    end

    test "the submitter cannot reject their own application either" do
      organisation = organisation_fixture()
      user = staff_member_in_organisation_fixture(organisation, "organisation_administrator")
      staff_member = Accounts.get_staff_member(user.id)
      scope = %Scope{user: user, staff_member: staff_member, organisation_id: organisation.id}

      customer = customer_fixture_in_organisation(organisation)
      {:ok, application} =
        Applications.create_application(scope, valid_application_attrs(%{"customer_id" => customer.id}))
      {:ok, application} = Applications.assess_application(application, scope)

      assert {:error, :maker_checker_violation} = Applications.reject_application(application, scope, "changed my mind")
    end

    test "a different staff member can approve it" do
      organisation = organisation_fixture()
      maker = staff_member_in_organisation_fixture(organisation, "loan_officer")
      maker_staff_member = Accounts.get_staff_member(maker.id)
      maker_scope = %Scope{user: maker, staff_member: maker_staff_member, organisation_id: organisation.id}

      checker = staff_member_in_organisation_fixture(organisation, "organisation_administrator")
      checker_staff_member = Accounts.get_staff_member(checker.id)
      checker_scope = %Scope{user: checker, staff_member: checker_staff_member, organisation_id: organisation.id}

      customer = customer_fixture_in_organisation(organisation)
      {:ok, application} =
        Applications.create_application(maker_scope, valid_application_attrs(%{"customer_id" => customer.id}))
      {:ok, application} = Applications.assess_application(application, checker_scope)

      assert {:ok, approved} = Applications.approve_application(application, checker_scope, true)
      assert approved.decided_by_id == checker.id
      assert application.created_by_id == maker.id
    end

    test "an application with no recorded maker (created_by_id nil) never blocks anyone" do
      application = application_fixture()
      assert application.created_by_id == nil

      admin = admin_fixture()
      scope = %Scope{user: admin, staff_member: Accounts.get_staff_member(admin.id), organisation_id: :all}
      {:ok, application} = Applications.assess_application(application, scope)
      assert {:ok, _approved} = Applications.approve_application(application, scope, true)
    end
  end
end
