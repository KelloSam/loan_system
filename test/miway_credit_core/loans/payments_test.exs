defmodule MiwayCreditCore.Loans.PaymentsTest do
  use MiwayCreditCore.DataCase, async: true

  import MiwayCreditCore.LoansFixtures
  import MiwayCreditCore.AccountsFixtures
  alias MiwayCreditCore.Loans
  alias MiwayCreditCore.Clients

  describe "record_payment/1" do
    test "deducts the payment amount from the account's outstanding balance" do
      application = approved_application_fixture()
      account = application.loan_account

      assert {:ok, transaction} = payment_result(account, "234.56")
      assert transaction.loan_account_id == account.id

      reloaded = Loans.get_account!(account.id)
      assert Decimal.equal?(reloaded.outstanding_balance, Decimal.sub(account.outstanding_balance, "234.56"))
      assert reloaded.status == "active"
    end

    test "allocates oldest-due-date-first, partially paying the earliest installment" do
      application = approved_application_fixture(%{"requested_term_months" => "3"})
      account = application.loan_account
      [first, second, third] = Loans.list_installments_for_account(account.id)

      # Rounded to the column's scale (numeric(15,2)) — Postgres rounds
      # on insert regardless, so comparing against an unrounded value
      # would spuriously fail.
      partial = first.scheduled_amount |> Decimal.div(Decimal.new("2")) |> Decimal.round(2)
      {:ok, transaction} = Loans.record_payment(valid_payment_attrs(account, %{"amount" => partial}))

      first_reloaded = Loans.get_installment!(first.id)
      assert first_reloaded.status == "partially_paid"
      assert Decimal.equal?(first_reloaded.paid_amount, partial)

      assert Loans.get_installment!(second.id).status == "upcoming"
      assert Loans.get_installment!(third.id).status == "upcoming"

      [allocation] = Loans.list_entries_for_account(account.id) |> Enum.filter(&(&1.source_id == transaction.id))
      assert Decimal.equal?(allocation.amount, Decimal.negate(partial))
    end

    test "a payment spanning more than one installment allocates across both" do
      application = approved_application_fixture(%{"requested_term_months" => "3"})
      account = application.loan_account
      [first, second, _third] = Loans.list_installments_for_account(account.id)

      half_second = second.scheduled_amount |> Decimal.div(Decimal.new("2")) |> Decimal.round(2)
      amount = Decimal.add(first.scheduled_amount, half_second)
      {:ok, _transaction} = Loans.record_payment(valid_payment_attrs(account, %{"amount" => amount}))

      assert Loans.get_installment!(first.id).status == "paid"
      assert Loans.get_installment!(second.id).status == "partially_paid"
    end

    test "closes the account when the balance reaches zero" do
      application = approved_application_fixture()
      account = application.loan_account
      {:ok, _transaction} = payment_result(account, account.outstanding_balance)

      reloaded = Loans.get_account!(account.id)
      assert Decimal.equal?(reloaded.outstanding_balance, Decimal.new("0.00"))
      assert reloaded.status == "closed"
      assert reloaded.closed_at
    end

    test "rejects a payment amount exceeding the outstanding balance" do
      application = approved_application_fixture()
      account = application.loan_account
      over = Decimal.add(account.outstanding_balance, Decimal.new("1"))

      assert {:error, :amount_exceeds_balance} = payment_result(account, over)
    end

    test "posts a repayment ledger entry with a correct running_balance" do
      application = approved_application_fixture()
      account = application.loan_account
      {:ok, transaction} = payment_result(account, "100.00")

      entries = Loans.list_entries_for_account(account.id)
      repayment = Enum.find(entries, &(&1.entry_type == "repayment"))

      assert repayment.source_id == transaction.id
      assert Decimal.equal?(repayment.amount, Decimal.new("-100.00"))

      reloaded = Loans.get_account!(account.id)
      assert Decimal.equal?(repayment.running_balance, reloaded.outstanding_balance)
      assert Decimal.equal?(Loans.rebuild_outstanding_balance(account.id), reloaded.outstanding_balance)
    end

    test "recalculates the client's current_balance after a payment" do
      application = approved_application_fixture()
      account = application.loan_account
      {:ok, _transaction} = payment_result(account, account.outstanding_balance)

      reloaded_client = Clients.get_client!(application.client_id)
      assert Decimal.equal?(reloaded_client.current_balance, Decimal.new("0.00"))
    end
  end

  describe "void_payment/2" do
    test "reverses the allocation, restores the balance, and reopens a closed account" do
      application = approved_application_fixture()
      account = application.loan_account
      {:ok, transaction} = payment_result(account, account.outstanding_balance)
      admin = admin_fixture()

      assert Loans.get_account!(account.id).status == "closed"

      assert {:ok, voided} =
               Loans.void_payment(transaction, %{"voided_by_id" => admin.id, "void_reason" => "Entered in error"})

      assert voided.status == "voided"

      reloaded_account = Loans.get_account!(account.id)
      assert reloaded_account.status == "active"
      assert Decimal.equal?(reloaded_account.outstanding_balance, account.outstanding_balance)

      installments = Loans.list_installments_for_account(account.id)
      assert Enum.all?(installments, &(&1.status != "paid"))
      assert Enum.all?(installments, &Decimal.equal?(&1.paid_amount, Decimal.new("0.00")))

      assert Decimal.equal?(Loans.rebuild_outstanding_balance(account.id), reloaded_account.outstanding_balance)
    end

    test "does not touch an already-voided transaction's status via a second void" do
      application = approved_application_fixture()
      account = application.loan_account
      {:ok, transaction} = payment_result(account, "50.00")
      admin = admin_fixture()

      {:ok, voided} = Loans.void_payment(transaction, %{"voided_by_id" => admin.id, "void_reason" => "test"})
      assert voided.status == "voided"

      assert_raise FunctionClauseError, fn ->
        Loans.void_payment(voided, %{"voided_by_id" => admin.id, "void_reason" => "again"})
      end
    end
  end

  defp payment_result(account, amount) do
    Loans.record_payment(valid_payment_attrs(account, %{"amount" => amount}))
  end
end
