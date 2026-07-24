defmodule MiwayCreditCore.Loans.ApplicationsTest do
  use MiwayCreditCore.DataCase, async: true

  import MiwayCreditCore.ClientsFixtures
  import MiwayCreditCore.AccountsFixtures
  import MiwayCreditCore.LoansFixtures
  alias MiwayCreditCore.Loans
  alias MiwayCreditCore.Loans.LoanApplication
  alias MiwayCreditCore.Clients

  describe "create_application/1" do
    test "creates a pending application and stamps a fraud-detector risk_level/risk_score" do
      client = client_fixture()

      assert {:ok, %LoanApplication{} = application} =
               Loans.create_application(valid_application_attrs(%{"client_id" => client.id}))

      assert application.status == "pending"
      # A brand-new client with no repayment history always scores at
      # least 35 (new_client +20, no_repayment_history +15) — always
      # "medium" or worse, never "low".
      assert application.risk_level in ["medium", "high"]
      assert application.risk_score >= 35
    end

    test "recalculates the client's total_loans; current_balance stays zero (no account yet)" do
      client = client_fixture()
      {:ok, _application} = Loans.create_application(valid_application_attrs(%{"client_id" => client.id}))

      reloaded = Clients.get_client!(client.id)
      assert reloaded.total_loans == 1
      assert Decimal.equal?(reloaded.current_balance, Decimal.new("0.00"))
    end

    test "blocks a second application while one is still pending" do
      client = client_fixture()
      {:ok, _first} = Loans.create_application(valid_application_attrs(%{"client_id" => client.id}))

      assert {:error, :pending_application_exists} =
               Loans.create_application(valid_application_attrs(%{"client_id" => client.id}))
    end

    test "blocks a new application within 30 days of a rejection" do
      client = client_fixture()
      application = application_fixture(%{"client_id" => client.id})
      admin = admin_fixture()
      {:ok, _rejected} = Loans.reject_application(application, admin.id, "Insufficient income")

      assert {:error, :rejection_cooldown} =
               Loans.create_application(valid_application_attrs(%{"client_id" => client.id}))
    end

    test "rejects invalid attrs with a changeset error" do
      client = client_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Loans.create_application(
                 valid_application_attrs(%{"client_id" => client.id, "requested_amount" => "-5"})
               )
    end
  end

  describe "fraud_signals/1" do
    test "lists the human-readable signals behind the risk score" do
      application = application_fixture()
      signals = Loans.fraud_signals(application)
      assert is_list(signals)
      assert Enum.any?(signals, &(&1 =~ "less than 7 days old"))
      assert Enum.any?(signals, &(&1 =~ "No repayment history"))
    end
  end

  describe "approve_application/2" do
    test "flips status, stamps decided_at/decided_by_id, and opens a LoanAccount" do
      application = application_fixture()
      admin = admin_fixture()

      assert {:ok, approved, account} = Loans.approve_application(application, admin.id)
      assert approved.status == "approved"
      assert approved.decided_at
      assert approved.decided_by_id == admin.id

      assert account.loan_application_id == approved.id
      assert account.client_id == approved.client_id
      assert account.status == "active"
      assert Decimal.compare(account.outstanding_balance, Decimal.new("0")) == :gt
    end

    test "the opening balance reconciles against the ledger's disbursement entry" do
      application = application_fixture()
      admin = admin_fixture()
      {:ok, _approved, account} = Loans.approve_application(application, admin.id)

      assert Decimal.equal?(Loans.rebuild_outstanding_balance(account.id), account.outstanding_balance)

      [entry] = Loans.list_entries_for_account(account.id)
      assert entry.entry_type == "disbursement"
      assert Decimal.equal?(entry.amount, account.outstanding_balance)
    end

    test "recalculates the client's current_balance to the new account's outstanding_balance" do
      application = application_fixture()
      admin = admin_fixture()
      {:ok, _approved, account} = Loans.approve_application(application, admin.id)

      reloaded_client = Clients.get_client!(application.client_id)
      assert Decimal.equal?(reloaded_client.current_balance, account.outstanding_balance)
    end

    test "generates a monthly repayment schedule matching the account's term" do
      application = application_fixture(%{"requested_term_months" => "3"})
      admin = admin_fixture()
      {:ok, _approved, account} = Loans.approve_application(application, admin.id)

      installments = Loans.list_installments_for_account(account.id)
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

      assert {:ok, rejected} = Loans.reject_application(application, admin.id, "Debt-to-income too high")
      assert rejected.status == "rejected"
      assert rejected.decided_at
      assert rejected.decided_by_id == admin.id
      assert rejected.rejection_reason == "Debt-to-income too high"
    end

    test "does not create a LoanAccount" do
      application = application_fixture()
      admin = admin_fixture()
      {:ok, rejected} = Loans.reject_application(application, admin.id, "Not eligible")

      assert Loans.get_application!(rejected.id).loan_account == nil
    end
  end

  describe "update_application/2 and delete_application/1" do
    test "update_application/2 updates permitted fields" do
      application = application_fixture()
      assert {:ok, updated} = Loans.update_application(application, %{"purpose" => "School fees"})
      assert updated.purpose == "School fees"
    end

    test "delete_application/1 removes the application and recalculates client stats" do
      application = application_fixture()
      assert {:ok, _} = Loans.delete_application(application)
      assert_raise Ecto.NoResultsError, fn -> Loans.get_application!(application.id) end

      reloaded_client = Clients.get_client!(application.client_id)
      assert reloaded_client.total_loans == 0
    end
  end

  describe "aggregate counters" do
    test "count_applications/0 and count_active_applications/0" do
      before_count = Loans.count_applications()
      active_before = Loans.count_active_applications()

      application = application_fixture()

      assert Loans.count_applications() == before_count + 1
      assert Loans.count_active_applications() == active_before + 1

      admin = admin_fixture()
      {:ok, _} = Loans.reject_application(application, admin.id, "Not eligible")
      assert Loans.count_active_applications() == active_before
    end
  end
end
