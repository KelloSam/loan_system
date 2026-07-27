defmodule MiwayCreditCore.ApplicationsTest do
  use MiwayCreditCore.DataCase, async: true

  import MiwayCreditCore.CustomersFixtures
  import MiwayCreditCore.AccountsFixtures
  import MiwayCreditCore.LoansFixtures
  import MiwayCreditCore.OrganisationsFixtures
  alias MiwayCreditCore.{Applications, Accounting, Lending}
  alias MiwayCreditCore.Applications.LoanApplication
  alias MiwayCreditCore.Customers
  alias MiwayCreditCore.Accounts.Scope

  describe "create_application/2" do
    test "creates a pending application and stamps a fraud-detector risk_level/risk_score" do
      customer = customer_fixture()
      scope = %Scope{organisation_id: customer.organisation_id}

      assert {:ok, %LoanApplication{} = application} =
               Applications.create_application(scope, valid_application_attrs(%{"customer_id" => customer.id}))

      assert application.status == "pending"
      assert application.organisation_id == customer.organisation_id
      # A brand-new customer with no repayment history always scores at
      # least 35 (new_customer +20, no_repayment_history +15) — always
      # "medium" or worse, never "low".
      assert application.risk_level in ["medium", "high"]
      assert application.risk_score >= 35
    end

    test "recalculates the customer's total_loans; current_balance stays zero (no account yet)" do
      customer = customer_fixture()
      scope = %Scope{organisation_id: customer.organisation_id}
      {:ok, _application} = Applications.create_application(scope, valid_application_attrs(%{"customer_id" => customer.id}))

      reloaded = Customers.get_customer!(scope, customer.id)
      assert reloaded.total_loans == 1
      assert Decimal.equal?(reloaded.current_balance, Decimal.new("0.00"))
    end

    test "blocks a second application while one is still pending" do
      customer = customer_fixture()
      scope = %Scope{organisation_id: customer.organisation_id}
      {:ok, _first} = Applications.create_application(scope, valid_application_attrs(%{"customer_id" => customer.id}))

      assert {:error, :pending_application_exists} =
               Applications.create_application(scope, valid_application_attrs(%{"customer_id" => customer.id}))
    end

    test "blocks a new application within 30 days of a rejection" do
      customer = customer_fixture()
      scope = %Scope{organisation_id: customer.organisation_id}
      application = application_fixture(%{"customer_id" => customer.id})
      admin = admin_fixture()
      {:ok, _rejected} = Applications.reject_application(application, admin.id, "Insufficient income")

      assert {:error, :rejection_cooldown} =
               Applications.create_application(scope, valid_application_attrs(%{"customer_id" => customer.id}))
    end

    test "rejects invalid attrs with a changeset error" do
      customer = customer_fixture()
      scope = %Scope{organisation_id: customer.organisation_id}

      assert {:error, %Ecto.Changeset{}} =
               Applications.create_application(
                 scope,
                 valid_application_attrs(%{"customer_id" => customer.id, "requested_amount" => "-5"})
               )
    end

    test "with scope :all (platform administrator), still derives organisation_id from the customer applied for" do
      customer = customer_fixture()

      assert {:ok, application} =
               Applications.create_application(
                 %Scope{organisation_id: :all},
                 valid_application_attrs(%{"customer_id" => customer.id})
               )

      assert application.organisation_id == customer.organisation_id
    end
  end

  describe "fraud_signals/1" do
    test "lists the human-readable signals behind the risk score" do
      application = application_fixture()
      signals = Applications.fraud_signals(application)
      assert is_list(signals)
      assert Enum.any?(signals, &(&1 =~ "less than 7 days old"))
      assert Enum.any?(signals, &(&1 =~ "No repayment history"))
    end
  end

  describe "approve_application/2" do
    test "flips status, stamps decided_at/decided_by_id, and opens a LoanAccount" do
      application = application_fixture()
      admin = admin_fixture()

      assert {:ok, approved, account} = Applications.approve_application(application, admin.id)
      assert approved.status == "approved"
      assert approved.decided_at
      assert approved.decided_by_id == admin.id

      assert account.loan_application_id == approved.id
      assert account.customer_id == approved.customer_id
      assert account.organisation_id == approved.organisation_id
      assert account.status == "active"
      assert Decimal.compare(account.outstanding_balance, Decimal.new("0")) == :gt
    end

    test "the opening balance reconciles against the ledger's disbursement entry" do
      application = application_fixture()
      scope = %Scope{organisation_id: application.organisation_id}
      admin = admin_fixture()
      {:ok, _approved, account} = Applications.approve_application(application, admin.id)

      assert Decimal.equal?(Accounting.rebuild_outstanding_balance(scope, account.id), account.outstanding_balance)

      [entry] = Accounting.list_entries_for_account(scope, account.id)
      assert entry.entry_type == "disbursement"
      assert Decimal.equal?(entry.amount, account.outstanding_balance)
    end

    test "recalculates the customer's current_balance to the new account's outstanding_balance" do
      application = application_fixture()
      scope = %Scope{organisation_id: application.organisation_id}
      admin = admin_fixture()
      {:ok, _approved, account} = Applications.approve_application(application, admin.id)

      reloaded_customer = Customers.get_customer!(scope, application.customer_id)
      assert Decimal.equal?(reloaded_customer.current_balance, account.outstanding_balance)
    end

    test "generates a monthly repayment schedule matching the account's term" do
      application = application_fixture(%{"requested_term_months" => "3"})
      scope = %Scope{organisation_id: application.organisation_id}
      admin = admin_fixture()
      {:ok, _approved, account} = Applications.approve_application(application, admin.id)

      installments = Lending.list_installments_for_account(scope, account.id)
      assert length(installments) == 3
      assert Enum.all?(installments, &(&1.status == "upcoming"))
      assert Enum.all?(installments, &Decimal.equal?(&1.paid_amount, Decimal.new("0.00")))

      due_dates = installments |> Enum.map(& &1.due_date) |> Enum.sort(Date)
      opened_date = DateTime.to_date(account.opened_at)
      assert Enum.at(due_dates, 0) == Timex.shift(opened_date, months: 1)
      assert Enum.at(due_dates, 1) == Timex.shift(opened_date, months: 2)
      assert Enum.at(due_dates, 2) == Timex.shift(opened_date, months: 3)

      total_scheduled = installments |> Enum.map(& &1.scheduled_amount) |> Enum.reduce(&Decimal.add/2)
      assert Decimal.equal?(total_scheduled, account.outstanding_balance)
    end
  end

  describe "reject_application/3" do
    test "sets status, decision fields, and rejection_reason" do
      application = application_fixture()
      admin = admin_fixture()

      assert {:ok, rejected} = Applications.reject_application(application, admin.id, "Debt-to-income too high")
      assert rejected.status == "rejected"
      assert rejected.decided_at
      assert rejected.decided_by_id == admin.id
      assert rejected.rejection_reason == "Debt-to-income too high"
    end

    test "does not create a LoanAccount" do
      application = application_fixture()
      scope = %Scope{organisation_id: application.organisation_id}
      admin = admin_fixture()
      {:ok, rejected} = Applications.reject_application(application, admin.id, "Not eligible")

      assert Applications.get_application!(scope, rejected.id).loan_account == nil
    end
  end

  describe "update_application/2 and delete_application/1" do
    test "update_application/2 updates permitted fields" do
      application = application_fixture()
      assert {:ok, updated} = Applications.update_application(application, %{"purpose" => "School fees"})
      assert updated.purpose == "School fees"
    end

    test "delete_application/1 removes the application and recalculates customer stats" do
      application = application_fixture()
      scope = %Scope{organisation_id: application.organisation_id}
      assert {:ok, _} = Applications.delete_application(application)
      assert_raise Ecto.NoResultsError, fn -> Applications.get_application!(scope, application.id) end

      reloaded_customer = Customers.get_customer!(scope, application.customer_id)
      assert reloaded_customer.total_loans == 0
    end
  end

  describe "aggregate counters" do
    test "count_applications/1 and count_active_applications/1 are scoped to one organisation" do
      organisation = organisation_fixture()
      scope = %Scope{organisation_id: organisation.id}
      customer = customer_fixture_in_organisation(organisation)

      assert Applications.count_applications(scope) == 0
      assert Applications.count_active_applications(scope) == 0

      application = application_fixture(%{"customer_id" => customer.id})

      assert Applications.count_applications(scope) == 1
      assert Applications.count_active_applications(scope) == 1

      admin = admin_fixture()
      {:ok, _} = Applications.reject_application(application, admin.id, "Not eligible")
      assert Applications.count_active_applications(scope) == 0
    end
  end
end
