defmodule MiwayCreditCore.LoansTest do
  use MiwayCreditCore.DataCase, async: true

  import MiwayCreditCore.ClientsFixtures
  import MiwayCreditCore.LoansFixtures
  alias MiwayCreditCore.Loans
  alias MiwayCreditCore.Loans.Loan
  alias MiwayCreditCore.Clients

  describe "create_loan/1" do
    test "creates a pending loan and stamps a fraud-detector risk_level" do
      client = client_fixture()
      assert {:ok, %Loan{} = loan} = Loans.create_loan(valid_loan_attrs(%{"client_id" => client.id}))
      assert loan.status == "pending"
      # A brand-new client with no repayment history always scores at
      # least 35 (new_client +20, no_repayment_history +15) — always
      # "medium" or worse, never "low".
      assert loan.risk_level in ["medium", "high"]
    end

    test "recalculates the client's total_loans and current_balance" do
      client = client_fixture()
      {:ok, loan} = Loans.create_loan(valid_loan_attrs(%{"client_id" => client.id}))

      reloaded = Clients.get_client!(client.id)
      assert reloaded.total_loans == 1
      assert Decimal.equal?(reloaded.current_balance, loan.remaining_balance)
    end

    test "blocks a second loan while one is still pending" do
      client = client_fixture()
      {:ok, _first} = Loans.create_loan(valid_loan_attrs(%{"client_id" => client.id}))

      assert {:error, :pending_loan_exists} =
               Loans.create_loan(valid_loan_attrs(%{"client_id" => client.id}))
    end

    test "blocks a new loan within 30 days of a rejection" do
      client = client_fixture()
      {:ok, loan} = Loans.create_loan(valid_loan_attrs(%{"client_id" => client.id}))
      {:ok, _rejected} = Loans.reject_loan(loan)

      assert {:error, :rejection_cooldown} =
               Loans.create_loan(valid_loan_attrs(%{"client_id" => client.id}))
    end

    test "rejects invalid attrs with a changeset error" do
      client = client_fixture()
      assert {:error, %Ecto.Changeset{}} =
               Loans.create_loan(valid_loan_attrs(%{"client_id" => client.id, "amount" => "-5"}))
    end
  end

  describe "fraud_signals/1" do
    test "lists the human-readable signals behind the risk score" do
      loan = loan_fixture()
      signals = Loans.fraud_signals(loan)
      assert is_list(signals)
      assert Enum.any?(signals, &(&1 =~ "less than 7 days old"))
      assert Enum.any?(signals, &(&1 =~ "No repayment history"))
    end
  end

  describe "approve_loan/1 and reject_loan/1" do
    test "approve_loan/1 sets status and approved_at, keeps balance in client stats" do
      loan = loan_fixture()
      assert {:ok, approved} = Loans.approve_loan(loan)
      assert approved.status == "approved"
      assert approved.approved_at

      reloaded_client = Clients.get_client!(loan.client_id)
      assert Decimal.equal?(reloaded_client.current_balance, loan.remaining_balance)
    end

    test "reject_loan/1 sets status and removes the loan from the client's balance" do
      loan = loan_fixture()
      assert {:ok, rejected} = Loans.reject_loan(loan)
      assert rejected.status == "rejected"

      reloaded_client = Clients.get_client!(loan.client_id)
      assert Decimal.equal?(reloaded_client.current_balance, Decimal.new("0.00"))
    end

    test "approving a loan generates a monthly repayment schedule" do
      loan = loan_fixture(%{"term_months" => "3"})
      {:ok, approved} = Loans.approve_loan(loan)

      schedule = Loans.list_payments_for_loan(approved.id)
      assert length(schedule) == 3
      assert Enum.all?(schedule, &(&1.status == "pending"))
      assert Enum.all?(schedule, &(&1.payment_date == nil))
      assert Enum.all?(schedule, &(&1.due_date != nil))

      interest = Loans.compound_interest_details(approved)
      assert Enum.all?(schedule, &Decimal.equal?(&1.amount, interest.monthly_payment))

      # due dates are monthly, starting a month after approval
      due_dates = schedule |> Enum.map(& &1.due_date) |> Enum.sort(Date)
      approved_date = NaiveDateTime.to_date(approved.approved_at)
      assert Enum.at(due_dates, 0) == Timex.shift(approved_date, months: 1)
      assert Enum.at(due_dates, 1) == Timex.shift(approved_date, months: 2)
      assert Enum.at(due_dates, 2) == Timex.shift(approved_date, months: 3)
    end

    test "generating the schedule twice does not duplicate it" do
      loan = loan_fixture(%{"term_months" => "2"})
      {:ok, approved} = Loans.approve_loan(loan)

      assert :ok = Loans.generate_repayment_schedule(approved)
      assert length(Loans.list_payments_for_loan(approved.id)) == 2
    end

    test "rejecting a loan does not generate a schedule" do
      loan = loan_fixture()
      {:ok, rejected} = Loans.reject_loan(loan)
      assert Loans.list_payments_for_loan(rejected.id) == []
    end
  end

  describe "update_loan/2 and delete_loan/1" do
    test "update_loan/2 updates permitted fields" do
      loan = loan_fixture()
      assert {:ok, updated} = Loans.update_loan(loan, %{"purpose" => "School fees"})
      assert updated.purpose == "School fees"
    end

    test "delete_loan/1 removes the loan and recalculates client stats" do
      loan = loan_fixture()
      assert {:ok, _} = Loans.delete_loan(loan)
      assert_raise Ecto.NoResultsError, fn -> Loans.get_loan!(loan.id) end

      reloaded_client = Clients.get_client!(loan.client_id)
      assert reloaded_client.total_loans == 0
      assert Decimal.equal?(reloaded_client.current_balance, Decimal.new("0.00"))
    end
  end

  describe "create_payment/1" do
    test "deducts the payment amount from the loan's remaining balance" do
      loan = approved_loan_fixture()
      assert {:ok, payment} = Loans.create_payment(valid_payment_attrs(loan, %{"amount" => "234.56"}))
      assert payment.loan_id == loan.id

      reloaded_loan = Loans.get_loan!(loan.id)
      assert Decimal.equal?(reloaded_loan.remaining_balance, Decimal.new("1000.00"))
      assert reloaded_loan.status == "approved"
    end

    test "marks the loan completed when the balance reaches zero" do
      loan = approved_loan_fixture()
      assert {:ok, _payment} = Loans.create_payment(valid_payment_attrs(loan, %{"amount" => "1234.56"}))

      reloaded_loan = Loans.get_loan!(loan.id)
      assert Decimal.equal?(reloaded_loan.remaining_balance, Decimal.new("0.00"))
      assert reloaded_loan.status == "completed"
    end

    test "rejects a payment amount exceeding the remaining balance" do
      loan = approved_loan_fixture()
      assert {:error, :amount_exceeds_balance} =
               Loans.create_payment(valid_payment_attrs(loan, %{"amount" => "5000.00"}))
    end

    test "recalculates the client's current_balance after a payment" do
      loan = approved_loan_fixture()
      {:ok, _payment} = Loans.create_payment(valid_payment_attrs(loan, %{"amount" => "1234.56"}))

      reloaded_client = Clients.get_client!(loan.client_id)
      assert Decimal.equal?(reloaded_client.current_balance, Decimal.new("0.00"))
    end
  end

  describe "payment queries" do
    test "list_payments_for_loan/1 and get_payment!/1" do
      loan = loan_fixture()
      payment = payment_fixture(loan, %{"amount" => "100.00"})

      assert [found] = Loans.list_payments_for_loan(loan.id)
      assert found.id == payment.id
      assert Loans.get_payment!(payment.id).id == payment.id
    end

    test "get_upcoming_payments/1 only returns pending, future-or-today payments for the client" do
      # approved_loan_fixture/1 now auto-generates a full repayment
      # schedule (one pending installment per month, see
      # generate_repayment_schedule/1) — those are legitimately
      # "upcoming" too, so this test accounts for them rather than
      # assuming only the manually-created payments below exist.
      loan = approved_loan_fixture()

      {:ok, upcoming} =
        Loans.create_payment(%{
          "loan_id" => loan.id,
          "amount" => "50.00",
          "due_date" => Date.add(Date.utc_today(), 10) |> Date.to_iso8601(),
          "status" => "pending"
        })

      {:ok, paid} =
        Loans.create_payment(%{
          "loan_id" => loan.id,
          "amount" => "50.00",
          "payment_date" => Date.to_iso8601(Date.utc_today()),
          "status" => "paid"
        })

      results = Loans.get_upcoming_payments(loan.client_id)
      ids = Enum.map(results, & &1.id)
      assert upcoming.id in ids
      refute paid.id in ids
      assert length(results) == loan.term_months + 1
    end
  end

  describe "aggregate counters" do
    test "count_loans/0, count_active_loans/0, total_outstanding_balance/0" do
      loans_before = Loans.count_loans()
      active_before = Loans.count_active_loans()
      outstanding_before = Loans.total_outstanding_balance()

      loan = loan_fixture()

      assert Loans.count_loans() == loans_before + 1
      assert Loans.count_active_loans() == active_before + 1
      assert Decimal.equal?(
               Loans.total_outstanding_balance(),
               Decimal.add(outstanding_before, loan.remaining_balance)
             )

      {:ok, _} = Loans.reject_loan(loan)
      assert Loans.count_active_loans() == active_before
    end
  end
end
