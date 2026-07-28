defmodule MiwayCreditCoreWeb.PermissionEnforcementTest do
  @moduledoc """
  The review-demo criteria from the Step 6 plan, as real HTTP tests:
  log in as each role and verify server-side what they can See,
  Create, Edit, Approve, and Reverse — a refusal must be a real 403,
  never a silently-hidden button that still works if you hit the URL
  directly.
  """

  use MiwayCreditCoreWeb.ConnCase, async: true

  import MiwayCreditCore.{CustomersFixtures, LoansFixtures, OrganisationsFixtures}

  alias MiwayCreditCore.{Applications, Payments}
  alias MiwayCreditCore.Accounts.Scope

  setup do
    organisation = organisation_fixture()
    loan_officer = staff_member_in_organisation_fixture(organisation, "loan_officer")
    org_admin = staff_member_in_organisation_fixture(organisation, "organisation_administrator")
    customer = customer_fixture_in_organisation(organisation)

    %{organisation: organisation, loan_officer: loan_officer, org_admin: org_admin, customer: customer}
  end

  describe "loan_officer — See, Create, Edit granted; Approve, Reverse refused" do
    test "See: can list and view applications", %{conn: conn, loan_officer: loan_officer, customer: customer} do
      application = application_fixture(%{"customer_id" => customer.id})

      conn = conn |> login(loan_officer)
      assert conn |> get(~p"/admin/loans") |> html_response(200)
      assert conn |> get(~p"/admin/loans/#{application.id}") |> html_response(200)
    end

    test "Create: can submit a new application", %{conn: conn, loan_officer: loan_officer, customer: customer} do
      conn = conn |> login(loan_officer)

      conn =
        post(conn, ~p"/admin/loans", loan_application: %{
          "customer_id" => customer.id,
          "requested_amount" => "1234.56",
          "requested_term_months" => "6"
        })

      assert redirected_to(conn) =~ ~r{^/admin/loans/}
    end

    test "Edit: can update a pending application", %{conn: conn, loan_officer: loan_officer, customer: customer} do
      application = application_fixture(%{"customer_id" => customer.id})
      conn = conn |> login(loan_officer)

      conn = patch(conn, ~p"/admin/loans/#{application.id}", loan_application: %{"purpose" => "School fees"})
      assert redirected_to(conn) == ~p"/admin/loans/#{application.id}"
    end

    test "Approve: refused with a real 403, not hidden", %{conn: conn, loan_officer: loan_officer, customer: customer} do
      application = application_fixture(%{"customer_id" => customer.id})
      conn = conn |> login(loan_officer) |> patch(~p"/admin/loans/#{application.id}/approve")

      assert conn.status == 403
    end

    test "Reject: refused with a real 403", %{conn: conn, loan_officer: loan_officer, customer: customer} do
      application = application_fixture(%{"customer_id" => customer.id})
      conn = conn |> login(loan_officer) |> patch(~p"/admin/loans/#{application.id}/reject", %{"reason" => "no"})

      assert conn.status == 403
    end

    test "Reverse (void a payment): refused with a real 403", %{
      conn: conn,
      loan_officer: loan_officer,
      organisation: organisation,
      customer: customer
    } do
      application = approved_application_fixture(%{"customer_id" => customer.id})
      scope = %Scope{organisation_id: organisation.id}
      {:ok, transaction} = Payments.record_payment(scope, valid_payment_attrs(application.loan_account, %{"amount" => "50.00"}))

      conn =
        conn
        |> login(loan_officer)
        |> patch(~p"/admin/loans/#{application.id}/payments/#{transaction.id}/void")

      assert conn.status == 403
    end

    test "audit log: refused with a real 403", %{conn: conn, loan_officer: loan_officer} do
      conn = conn |> login(loan_officer) |> get(~p"/admin/audit-logs")
      assert conn.status == 403
    end
  end

  describe "organisation_administrator — Approve and Reverse both granted" do
    test "Approve: succeeds, disbursing the loan", %{conn: conn, org_admin: org_admin, customer: customer} do
      application = application_fixture(%{"customer_id" => customer.id})
      conn = conn |> login(org_admin)

      conn = patch(conn, ~p"/admin/loans/#{application.id}/approve")
      assert redirected_to(conn) == ~p"/admin/loans/#{application.id}"

      reloaded = Applications.get_application!(%Scope{organisation_id: :all}, application.id)
      assert reloaded.status == "approved"
      assert reloaded.loan_account != nil
    end

    test "Reverse (void a payment): succeeds", %{conn: conn, org_admin: org_admin, organisation: organisation, customer: customer} do
      application = approved_application_fixture(%{"customer_id" => customer.id})
      scope = %Scope{organisation_id: organisation.id}
      {:ok, transaction} = Payments.record_payment(scope, valid_payment_attrs(application.loan_account, %{"amount" => "50.00"}))

      conn = conn |> login(org_admin)
      conn = patch(conn, ~p"/admin/loans/#{application.id}/payments/#{transaction.id}/void", %{"reason" => "test"})

      assert redirected_to(conn) == ~p"/admin/loans/#{application.id}"
    end

    test "maker-checker still applies even to an organisation_administrator", %{conn: conn, org_admin: org_admin, customer: customer} do
      conn = conn |> login(org_admin)

      conn =
        post(conn, ~p"/admin/loans", loan_application: %{
          "customer_id" => customer.id,
          "requested_amount" => "1234.56",
          "requested_term_months" => "6"
        })

      application_path = redirected_to(conn)
      application_id = application_path |> String.split("/") |> List.last()

      conn2 = patch(conn, ~p"/admin/loans/#{application_id}/approve")
      assert Phoenix.Flash.get(conn2.assigns.flash, :error) =~ "submitted this application"
    end

    test "audit log: granted", %{conn: conn, org_admin: org_admin} do
      conn = conn |> login(org_admin)
      assert conn |> get(~p"/admin/audit-logs") |> html_response(200)
    end
  end

  describe "customers.manage — required for every KYC write action; a staff member with no permissions is refused" do
    test "loan_officer (granted customers.manage by default) can add a next of kin", %{
      conn: conn,
      loan_officer: loan_officer,
      customer: customer
    } do
      conn = conn |> login(loan_officer)

      conn =
        post(conn, ~p"/admin/customers/#{customer.id}/next_of_kin",
          next_of_kin: %{"name" => "Jane", "relationship" => "Sister", "phone" => "260971111111"}
        )

      assert redirected_to(conn) == ~p"/admin/customers/#{customer.id}"
    end

    test "org_admin can submit and verify KYC", %{conn: conn, org_admin: org_admin, customer: customer} do
      conn = conn |> login(org_admin)
      conn = patch(conn, ~p"/admin/customers/#{customer.id}/kyc/submit")
      assert redirected_to(conn) == ~p"/admin/customers/#{customer.id}"

      conn = conn |> patch(~p"/admin/customers/#{customer.id}/kyc/verify")
      assert redirected_to(conn) == ~p"/admin/customers/#{customer.id}"
    end

    test "a staff member with no RoleAssignment at all is refused a real 403 on every KYC write action", %{
      conn: conn,
      organisation: organisation,
      customer: customer
    } do
      {:ok, user, staff_member} =
        MiwayCreditCore.AccountsFixtures.valid_user_attrs()
        |> MiwayCreditCore.Accounts.register_staff_member("loan_officer")

      {:ok, _membership} = MiwayCreditCore.Organisations.add_staff_to_organisation(staff_member.id, organisation.id)

      conn = conn |> login(user)

      assert conn |> post(~p"/admin/customers/#{customer.id}/next_of_kin", next_of_kin: %{}) |> Map.fetch!(:status) == 403
      assert conn |> post(~p"/admin/customers/#{customer.id}/guarantors", guarantor: %{}) |> Map.fetch!(:status) == 403
      assert conn |> post(~p"/admin/customers/#{customer.id}/consents", consent: %{}) |> Map.fetch!(:status) == 403
      assert conn |> patch(~p"/admin/customers/#{customer.id}/kyc/submit") |> Map.fetch!(:status) == 403
    end

    test "a staff member with no RoleAssignment at all is refused even read access", %{
      conn: conn,
      organisation: organisation
    } do
      {:ok, user, staff_member} =
        MiwayCreditCore.AccountsFixtures.valid_user_attrs()
        |> MiwayCreditCore.Accounts.register_staff_member("loan_officer")

      {:ok, _membership} = MiwayCreditCore.Organisations.add_staff_to_organisation(staff_member.id, organisation.id)

      conn = conn |> login(user)
      assert conn |> get(~p"/admin/customers") |> Map.fetch!(:status) == 403
    end
  end

  defp login(conn, user) do
    conn
    |> Plug.Conn.put_session(:user_id, user.id)
    |> Plug.Conn.put_session(:authenticated_at, NaiveDateTime.utc_now())
  end
end
