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

  alias MiwayCreditCore.{Applications, Payments, Lending}
  alias MiwayCreditCore.Accounts.Scope

  setup do
    organisation = organisation_fixture()
    loan_officer = staff_member_in_organisation_fixture(organisation, "loan_officer")
    org_admin = staff_member_in_organisation_fixture(organisation, "organisation_administrator")
    customer = customer_fixture_in_organisation(organisation)

    %{organisation: organisation, loan_officer: loan_officer, org_admin: org_admin, customer: customer}
  end

  describe "loan_officer — See, Create, Edit, Assess, Withdraw granted; Approve, Reject, Disburse, Reverse refused" do
    test "See: can list and view applications", %{conn: conn, loan_officer: loan_officer, customer: customer} do
      application = application_fixture(%{"customer_id" => customer.id})

      conn = conn |> login(loan_officer)
      assert conn |> get(~p"/admin/loans") |> html_response(200)
      assert conn |> get(~p"/admin/loans/#{application.id}") |> html_response(200)
    end

    test "Create: can submit a new application", %{
      conn: conn,
      loan_officer: loan_officer,
      organisation: organisation,
      customer: customer
    } do
      conn = conn |> login(loan_officer)

      conn =
        post(conn, ~p"/admin/loans", loan_application: %{
          "customer_id" => customer.id,
          "loan_product_id" => default_product_id(organisation.id),
          "requested_amount" => "1234.56",
          "requested_term_months" => "6"
        })

      assert redirected_to(conn) =~ ~r/^\/admin\/loans\/[0-9a-f-]{36}$/
    end

    test "Edit: can update a pending application", %{conn: conn, loan_officer: loan_officer, customer: customer} do
      application = application_fixture(%{"customer_id" => customer.id})
      conn = conn |> login(loan_officer)

      conn = patch(conn, ~p"/admin/loans/#{application.id}", loan_application: %{"purpose" => "School fees"})
      assert redirected_to(conn) == ~p"/admin/loans/#{application.id}"
    end

    test "Assess: granted", %{conn: conn, loan_officer: loan_officer, customer: customer} do
      application = application_fixture(%{"customer_id" => customer.id})
      conn = conn |> login(loan_officer) |> patch(~p"/admin/loans/#{application.id}/assess")

      assert redirected_to(conn) == ~p"/admin/loans/#{application.id}"
    end

    test "Withdraw: granted", %{conn: conn, loan_officer: loan_officer, customer: customer} do
      application = application_fixture(%{"customer_id" => customer.id})
      conn = conn |> login(loan_officer) |> patch(~p"/admin/loans/#{application.id}/withdraw")

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

    test "Disburse: refused with a real 403", %{conn: conn, loan_officer: loan_officer, org_admin: org_admin, customer: customer} do
      application = application_fixture(%{"customer_id" => customer.id})

      admin_conn = conn |> login(org_admin)
      admin_conn = patch(admin_conn, ~p"/admin/loans/#{application.id}/assess")
      _admin_conn = patch(admin_conn, ~p"/admin/loans/#{application.id}/approve", %{"conflict_of_interest_confirmed" => "true"})

      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{})
        |> login(loan_officer)
        |> patch(~p"/admin/loans/#{application.id}/disburse")

      assert conn.status == 403
    end

    test "Reverse Disbursement: refused with a real 403", %{conn: conn, loan_officer: loan_officer, customer: customer} do
      application = approved_application_fixture(%{"customer_id" => customer.id})

      conn =
        conn
        |> login(loan_officer)
        |> patch(~p"/admin/loans/#{application.id}/reverse_disbursement", %{"reason" => "Wrong customer"})

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

    test "Log Failed Payment Attempt: granted (same tier as recording a real payment)", %{
      conn: conn,
      loan_officer: loan_officer,
      customer: customer
    } do
      application = approved_application_fixture(%{"customer_id" => customer.id})
      conn = conn |> login(loan_officer)

      conn =
        post(conn, ~p"/admin/loans/#{application.id}/payments/failed", payment: %{
          "amount" => "50.00",
          "method" => "mobile_money",
          "received_at" => Date.utc_today() |> Date.to_iso8601(),
          "fail_reason" => "No matching funds received"
        })

      assert redirected_to(conn) == ~p"/admin/loans/#{application.id}"
    end

    test "Mark Payment Failed: refused with a real 403", %{
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
        |> patch(~p"/admin/loans/#{application.id}/payments/#{transaction.id}/fail", %{"reason" => "Cheque bounced"})

      assert conn.status == 403
    end

    test "Receipt: can view (same tier as viewing the application)", %{
      conn: conn,
      loan_officer: loan_officer,
      organisation: organisation,
      customer: customer
    } do
      application = approved_application_fixture(%{"customer_id" => customer.id})
      scope = %Scope{organisation_id: organisation.id}
      {:ok, transaction} = Payments.record_payment(scope, valid_payment_attrs(application.loan_account, %{"amount" => "50.00"}))

      conn = conn |> login(loan_officer) |> get(~p"/admin/loans/#{application.id}/payments/#{transaction.id}/receipt")

      assert html_response(conn, 200)
    end

    test "audit log: refused with a real 403", %{conn: conn, loan_officer: loan_officer} do
      conn = conn |> login(loan_officer) |> get(~p"/admin/audit-logs")
      assert conn.status == 403
    end
  end

  describe "organisation_administrator — Approve, Disburse, and Reverse all granted" do
    test "Assess then Approve: succeeds, decision recorded but no account yet", %{conn: conn, org_admin: org_admin, customer: customer} do
      application = application_fixture(%{"customer_id" => customer.id})
      conn = conn |> login(org_admin)

      conn = patch(conn, ~p"/admin/loans/#{application.id}/assess")
      assert redirected_to(conn) == ~p"/admin/loans/#{application.id}"

      conn = patch(conn, ~p"/admin/loans/#{application.id}/approve", %{"conflict_of_interest_confirmed" => "true"})
      assert redirected_to(conn) == ~p"/admin/loans/#{application.id}"

      reloaded = Applications.get_application!(%Scope{organisation_id: :all}, application.id)
      assert reloaded.status == "approved"
      assert reloaded.loan_account == nil
    end

    test "Disburse: succeeds, opening the account — only reachable after approval", %{conn: conn, org_admin: org_admin, customer: customer} do
      application = application_fixture(%{"customer_id" => customer.id})
      conn = conn |> login(org_admin)

      conn = patch(conn, ~p"/admin/loans/#{application.id}/assess")
      conn = patch(conn, ~p"/admin/loans/#{application.id}/approve", %{"conflict_of_interest_confirmed" => "true"})

      conn = patch(conn, ~p"/admin/loans/#{application.id}/disburse")
      assert redirected_to(conn) == ~p"/admin/loans/#{application.id}"

      reloaded = Applications.get_application!(%Scope{organisation_id: :all}, application.id)
      assert reloaded.status == "disbursed"
      assert reloaded.loan_account != nil
    end

    test "Reverse Disbursement: succeeds before any payment is recorded", %{conn: conn, org_admin: org_admin, customer: customer} do
      application = approved_application_fixture(%{"customer_id" => customer.id})
      conn = conn |> login(org_admin)

      conn = patch(conn, ~p"/admin/loans/#{application.id}/reverse_disbursement", %{"reason" => "Wrong customer"})
      assert redirected_to(conn) == ~p"/admin/loans/#{application.id}"

      reloaded_account = Lending.get_account!(%Scope{organisation_id: :all}, application.loan_account.id)
      assert reloaded_account.status == "reversed"
    end

    test "Reverse (void a payment): succeeds", %{conn: conn, org_admin: org_admin, organisation: organisation, customer: customer} do
      application = approved_application_fixture(%{"customer_id" => customer.id})
      scope = %Scope{organisation_id: organisation.id}
      {:ok, transaction} = Payments.record_payment(scope, valid_payment_attrs(application.loan_account, %{"amount" => "50.00"}))

      conn = conn |> login(org_admin)
      conn = patch(conn, ~p"/admin/loans/#{application.id}/payments/#{transaction.id}/void", %{"reason" => "test"})

      assert redirected_to(conn) == ~p"/admin/loans/#{application.id}"
    end

    test "Mark Payment Failed: succeeds", %{conn: conn, org_admin: org_admin, organisation: organisation, customer: customer} do
      application = approved_application_fixture(%{"customer_id" => customer.id})
      scope = %Scope{organisation_id: organisation.id}
      {:ok, transaction} = Payments.record_payment(scope, valid_payment_attrs(application.loan_account, %{"amount" => "50.00"}))

      conn = conn |> login(org_admin)
      conn = patch(conn, ~p"/admin/loans/#{application.id}/payments/#{transaction.id}/fail", %{"reason" => "Cheque bounced"})

      assert redirected_to(conn) == ~p"/admin/loans/#{application.id}"

      reloaded = Payments.get_transaction!(scope, transaction.id)
      assert reloaded.status == "failed"
    end

    test "maker-checker still applies even to an organisation_administrator", %{
      conn: conn,
      org_admin: org_admin,
      organisation: organisation,
      customer: customer
    } do
      conn = conn |> login(org_admin)

      conn =
        post(conn, ~p"/admin/loans", loan_application: %{
          "customer_id" => customer.id,
          "loan_product_id" => default_product_id(organisation.id),
          "requested_amount" => "1234.56",
          "requested_term_months" => "6"
        })

      application_path = redirected_to(conn)
      application_id = application_path |> String.split("/") |> List.last()

      conn = patch(conn, ~p"/admin/loans/#{application_id}/assess")
      conn2 = patch(conn, ~p"/admin/loans/#{application_id}/approve", %{"conflict_of_interest_confirmed" => "true"})
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
      assert conn |> post(~p"/admin/customers/#{customer.id}/credit_reports", credit_report: %{}) |> Map.fetch!(:status) == 403
    end

    test "loan_officer (granted customers.manage by default) can record a credit report once consent is on file", %{
      conn: conn,
      loan_officer: loan_officer,
      customer: customer
    } do
      conn = conn |> login(loan_officer)

      conn =
        post(conn, ~p"/admin/customers/#{customer.id}/consents",
          consent: %{"consent_type" => "credit_check", "method" => "signed_form"}
        )

      assert redirected_to(conn) == ~p"/admin/customers/#{customer.id}"

      conn =
        post(conn, ~p"/admin/customers/#{customer.id}/credit_reports",
          credit_report: %{"outcome" => "clear", "checked_at" => Date.utc_today()}
        )

      assert redirected_to(conn) == ~p"/admin/customers/#{customer.id}"
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

  describe "conditionally_approve, refer, clear_conditions — same permission tier as approve/reject" do
    test "loan_officer is refused a real 403 on conditionally_approve", %{conn: conn, loan_officer: loan_officer, customer: customer} do
      application = application_fixture(%{"customer_id" => customer.id})

      conn =
        conn
        |> login(loan_officer)
        |> patch(~p"/admin/loans/#{application.id}/conditionally_approve", %{
          "conditions" => "x",
          "conflict_of_interest_confirmed" => "true"
        })

      assert conn.status == 403
    end

    test "loan_officer is refused a real 403 on refer", %{conn: conn, loan_officer: loan_officer, customer: customer} do
      application = application_fixture(%{"customer_id" => customer.id})

      conn = conn |> login(loan_officer) |> patch(~p"/admin/loans/#{application.id}/refer", %{"reason" => "need docs"})
      assert conn.status == 403
    end

    test "org_admin can conditionally approve, then must clear conditions before disbursing", %{conn: conn, org_admin: org_admin, customer: customer} do
      application = application_fixture(%{"customer_id" => customer.id})
      conn = conn |> login(org_admin)
      conn = patch(conn, ~p"/admin/loans/#{application.id}/assess")

      conn =
        patch(conn, ~p"/admin/loans/#{application.id}/conditionally_approve", %{
          "conditions" => "Provide payslip",
          "conflict_of_interest_confirmed" => "true"
        })

      assert redirected_to(conn) == ~p"/admin/loans/#{application.id}"

      reloaded = Applications.get_application!(%Scope{organisation_id: :all}, application.id)
      assert reloaded.status == "approved"
      assert reloaded.conditions == "Provide payslip"

      conn = patch(conn, ~p"/admin/loans/#{application.id}/disburse")
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "conditions must be cleared"

      conn = patch(conn, ~p"/admin/loans/#{application.id}/clear_conditions")
      assert redirected_to(conn) == ~p"/admin/loans/#{application.id}"

      conn = patch(conn, ~p"/admin/loans/#{application.id}/disburse")
      assert redirected_to(conn) == ~p"/admin/loans/#{application.id}"
    end

    test "org_admin can refer an application back, then re-assess and approve it", %{conn: conn, org_admin: org_admin, customer: customer} do
      application = application_fixture(%{"customer_id" => customer.id})
      conn = conn |> login(org_admin)
      conn = patch(conn, ~p"/admin/loans/#{application.id}/assess")

      conn = patch(conn, ~p"/admin/loans/#{application.id}/refer", %{"reason" => "Need proof of income"})
      assert redirected_to(conn) == ~p"/admin/loans/#{application.id}"

      reloaded = Applications.get_application!(%Scope{organisation_id: :all}, application.id)
      assert reloaded.status == "referred"

      conn = patch(conn, ~p"/admin/loans/#{application.id}/assess")
      conn = patch(conn, ~p"/admin/loans/#{application.id}/approve", %{"conflict_of_interest_confirmed" => "true"})
      assert redirected_to(conn) == ~p"/admin/loans/#{application.id}"

      reloaded = Applications.get_application!(%Scope{organisation_id: :all}, application.id)
      assert reloaded.status == "approved"
    end
  end

  describe "products.view / products.manage — loan_officer can see, only org_admin can write" do
    test "loan_officer can list products (granted products.view by default)", %{conn: conn, loan_officer: loan_officer} do
      conn = conn |> login(loan_officer) |> get(~p"/admin/products")
      assert html_response(conn, 200)
    end

    test "loan_officer is refused a real 403 creating a product", %{conn: conn, loan_officer: loan_officer} do
      conn = conn |> login(loan_officer) |> get(~p"/admin/products/new")
      assert conn.status == 403
    end

    test "loan_officer is refused a real 403 posting a new product directly, not just hidden from the menu", %{
      conn: conn,
      loan_officer: loan_officer
    } do
      conn =
        conn
        |> login(loan_officer)
        |> post(~p"/admin/products", product: valid_product_attrs())

      assert conn.status == 403
    end

    test "org_admin can create, edit, retire, and reactivate a product", %{conn: conn, org_admin: org_admin} do
      conn = conn |> login(org_admin)

      conn = post(conn, ~p"/admin/products", product: valid_product_attrs())
      assert redirected_to(conn) == ~p"/admin/products"

      product = MiwayCreditCore.Repo.get_by!(MiwayCreditCore.Products.LoanProduct, name: valid_product_attrs()["name"])

      conn = patch(conn, ~p"/admin/products/#{product.id}", product: %{"interest_rate" => "20.00"})
      assert redirected_to(conn) == ~p"/admin/products"

      conn = patch(conn, ~p"/admin/products/#{product.id}/retire")
      assert redirected_to(conn) == ~p"/admin/products"
      assert MiwayCreditCore.Repo.get!(MiwayCreditCore.Products.LoanProduct, product.id).status == "retired"

      conn = patch(conn, ~p"/admin/products/#{product.id}/activate")
      assert redirected_to(conn) == ~p"/admin/products"
      assert MiwayCreditCore.Repo.get!(MiwayCreditCore.Products.LoanProduct, product.id).status == "active"
    end
  end

  defp valid_product_attrs do
    %{
      "name" => "Permission Test Product",
      "minimum_principal" => "100.00",
      "maximum_principal" => "50000.00",
      "interest_method" => "reducing_balance",
      "interest_rate" => "18.00",
      "minimum_term_months" => "1",
      "maximum_term_months" => "24",
      "repayment_frequency" => "monthly",
      "effective_from" => Date.utc_today()
    }
  end

  defp login(conn, user) do
    conn
    |> Plug.Conn.put_session(:user_id, user.id)
    |> Plug.Conn.put_session(:authenticated_at, NaiveDateTime.utc_now())
  end
end
