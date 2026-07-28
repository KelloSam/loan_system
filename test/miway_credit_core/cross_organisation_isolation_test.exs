defmodule MiwayCreditCore.CrossOrganisationIsolationTest do
  @moduledoc """
  The critical isolation test named in Step 5's plan: a user belonging
  to one organisation must never be able to reach another
  organisation's records — even by taking a valid record id and
  substituting it into a URL or a context call directly. Every
  fetch-by-id function added during the Step 5 retrofit is exercised
  here, at both the context layer and the HTTP layer, and this must
  keep passing before any further step (roles/permissions, KYC, loan
  products, application lifecycle...) is built on top of it.
  """

  use MiwayCreditCoreWeb.ConnCase, async: true

  import MiwayCreditCore.{CustomersFixtures, LoansFixtures, AccountsFixtures, OrganisationsFixtures}

  alias MiwayCreditCore.{Applications, Lending, Payments, Customers}
  alias MiwayCreditCore.Accounts.Scope

  # Builds a full "world" for one organisation: a loan_officer staff
  # member, a customer, an approved application with its account,
  # a posted payment, and a piece of collateral — one instance of
  # every org-owned resource type this retrofit added scoping to.
  defp build_world do
    organisation = organisation_fixture()
    scope = %Scope{organisation_id: organisation.id}
    staff_user = staff_member_in_organisation_fixture(organisation)
    customer = customer_fixture_in_organisation(organisation)

    application = application_fixture(%{"customer_id" => customer.id})
    admin = admin_fixture()
    {:ok, approved, account} = Applications.approve_application(application, %Scope{user: admin, organisation_id: :all})

    {:ok, transaction} = Payments.record_payment(scope, valid_payment_attrs(account, %{"amount" => "50.00"}))
    {:ok, collateral} = Applications.create_collateral(account, %{"type" => "vehicle", "description" => "Car", "estimated_value" => "10000.00"})
    [installment | _] = Lending.list_installments_for_account(scope, account.id)

    %{
      organisation: organisation,
      scope: scope,
      staff_user: staff_user,
      customer: customer,
      application: approved,
      account: account,
      transaction: transaction,
      collateral: collateral,
      installment: installment
    }
  end

  describe "context layer — fetch-by-id across organisations" do
    setup do
      %{org_a: build_world(), org_b: build_world()}
    end

    test "Customers.get_customer!/2 refuses another organisation's customer", %{org_a: a, org_b: b} do
      assert_raise Ecto.NoResultsError, fn -> Customers.get_customer!(a.scope, b.customer.id) end
    end

    test "Applications.get_application!/2 refuses another organisation's application", %{org_a: a, org_b: b} do
      assert_raise Ecto.NoResultsError, fn -> Applications.get_application!(a.scope, b.application.id) end
    end

    test "Applications.get_collateral!/2 refuses another organisation's collateral", %{org_a: a, org_b: b} do
      assert_raise Ecto.NoResultsError, fn -> Applications.get_collateral!(a.scope, b.collateral.id) end
    end

    test "Lending.get_account!/2 refuses another organisation's account", %{org_a: a, org_b: b} do
      assert_raise Ecto.NoResultsError, fn -> Lending.get_account!(a.scope, b.account.id) end
    end

    test "Lending.get_installment!/2 refuses another organisation's installment", %{org_a: a, org_b: b} do
      assert_raise Ecto.NoResultsError, fn -> Lending.get_installment!(a.scope, b.installment.id) end
    end

    test "Payments.get_transaction!/2 refuses another organisation's payment transaction", %{org_a: a, org_b: b} do
      assert_raise Ecto.NoResultsError, fn -> Payments.get_transaction!(a.scope, b.transaction.id) end
    end

    test "list/aggregate functions never include another organisation's rows", %{org_a: a, org_b: b} do
      refute b.customer.id in Enum.map(Customers.list_customers(a.scope), & &1.id)
      refute b.application.id in Enum.map(Applications.list_applications(a.scope), & &1.id)
      refute b.collateral.id in Enum.map(Applications.list_collaterals_for_account(a.scope, b.account.id), & &1.id)
      assert Applications.list_collaterals_for_account(a.scope, b.account.id) == []
    end

    test "a platform administrator's :all scope legitimately sees every organisation", %{org_a: a, org_b: b} do
      platform_scope = %Scope{organisation_id: :all}

      assert Customers.get_customer!(platform_scope, a.customer.id).id == a.customer.id
      assert Customers.get_customer!(platform_scope, b.customer.id).id == b.customer.id
      assert Applications.get_application!(platform_scope, a.application.id).id == a.application.id
      assert Applications.get_application!(platform_scope, b.application.id).id == b.application.id
    end
  end

  describe "HTTP layer — a real staff session cannot reach another organisation's records by URL" do
    setup do
      %{org_a: build_world(), org_b: build_world()}
    end

    test "GET /admin/customers/:id for another organisation's customer is refused, not served", %{
      conn: conn,
      org_a: a,
      org_b: b
    } do
      conn = login(conn, a.staff_user)

      assert_error_sent 404, fn ->
        get(conn, ~p"/admin/customers/#{b.customer.id}")
      end
    end

    test "GET /admin/loans/:id for another organisation's application is refused, not served", %{
      conn: conn,
      org_a: a,
      org_b: b
    } do
      conn = login(conn, a.staff_user)

      assert_error_sent 404, fn ->
        get(conn, ~p"/admin/loans/#{b.application.id}")
      end
    end

    test "the same staff session correctly reaches its own organisation's records", %{conn: conn, org_a: a} do
      conn1 = conn |> login(a.staff_user) |> get(~p"/admin/customers/#{a.customer.id}")
      assert html_response(conn1, 200) =~ a.customer.name

      conn2 = conn |> login(a.staff_user) |> get(~p"/admin/loans/#{a.application.id}")
      assert html_response(conn2, 200)
    end
  end

  defp login(conn, user) do
    conn
    |> Plug.Conn.put_session(:user_id, user.id)
    |> Plug.Conn.put_session(:authenticated_at, NaiveDateTime.utc_now())
  end
end
