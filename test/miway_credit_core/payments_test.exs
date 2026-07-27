defmodule MiwayCreditCore.PaymentsTest do
  use MiwayCreditCore.DataCase, async: true

  import MiwayCreditCore.LoansFixtures
  import MiwayCreditCore.AccountsFixtures
  alias MiwayCreditCore.{Payments, Lending, Accounting, Customers}
  alias MiwayCreditCore.Accounts.Scope

  describe "record_payment/2" do
    test "deducts the payment amount from the account's outstanding balance" do
      application = approved_application_fixture()
      scope = %Scope{organisation_id: application.organisation_id}
      account = application.loan_account

      assert {:ok, transaction} = payment_result(scope, account, "234.56")
      assert transaction.loan_account_id == account.id

      reloaded = Lending.get_account!(scope, account.id)
      assert Decimal.equal?(reloaded.outstanding_balance, Decimal.sub(account.outstanding_balance, "234.56"))
      assert reloaded.status == "active"
    end

    test "allocates oldest-due-date-first, partially paying the earliest installment" do
      application = approved_application_fixture(%{"requested_term_months" => "3"})
      scope = %Scope{organisation_id: application.organisation_id}
      account = application.loan_account
      [first, second, third] = Lending.list_installments_for_account(scope, account.id)

      # Rounded to the column's scale (numeric(15,2)) — Postgres rounds
      # on insert regardless, so comparing against an unrounded value
      # would spuriously fail.
      partial = first.scheduled_amount |> Decimal.div(Decimal.new("2")) |> Decimal.round(2)
      {:ok, transaction} = Payments.record_payment(scope, valid_payment_attrs(account, %{"amount" => partial}))

      first_reloaded = Lending.get_installment!(scope, first.id)
      assert first_reloaded.status == "partially_paid"
      assert Decimal.equal?(first_reloaded.paid_amount, partial)

      assert Lending.get_installment!(scope, second.id).status == "upcoming"
      assert Lending.get_installment!(scope, third.id).status == "upcoming"

      [allocation] = Accounting.list_entries_for_account(scope, account.id) |> Enum.filter(&(&1.source_id == transaction.id))
      assert Decimal.equal?(allocation.amount, Decimal.negate(partial))
    end

    test "a payment spanning more than one installment allocates across both" do
      application = approved_application_fixture(%{"requested_term_months" => "3"})
      scope = %Scope{organisation_id: application.organisation_id}
      account = application.loan_account
      [first, second, _third] = Lending.list_installments_for_account(scope, account.id)

      half_second = second.scheduled_amount |> Decimal.div(Decimal.new("2")) |> Decimal.round(2)
      amount = Decimal.add(first.scheduled_amount, half_second)
      {:ok, _transaction} = Payments.record_payment(scope, valid_payment_attrs(account, %{"amount" => amount}))

      assert Lending.get_installment!(scope, first.id).status == "paid"
      assert Lending.get_installment!(scope, second.id).status == "partially_paid"
    end

    test "closes the account when the balance reaches zero" do
      application = approved_application_fixture()
      scope = %Scope{organisation_id: application.organisation_id}
      account = application.loan_account
      {:ok, _transaction} = payment_result(scope, account, account.outstanding_balance)

      reloaded = Lending.get_account!(scope, account.id)
      assert Decimal.equal?(reloaded.outstanding_balance, Decimal.new("0.00"))
      assert reloaded.status == "closed"
      assert reloaded.closed_at
    end

    test "rejects a payment amount exceeding the outstanding balance" do
      application = approved_application_fixture()
      scope = %Scope{organisation_id: application.organisation_id}
      account = application.loan_account
      over = Decimal.add(account.outstanding_balance, Decimal.new("1"))

      assert {:error, :amount_exceeds_balance} = payment_result(scope, account, over)
    end

    test "posts a repayment ledger entry with a correct running_balance" do
      application = approved_application_fixture()
      scope = %Scope{organisation_id: application.organisation_id}
      account = application.loan_account
      {:ok, transaction} = payment_result(scope, account, "100.00")

      entries = Accounting.list_entries_for_account(scope, account.id)
      repayment = Enum.find(entries, &(&1.entry_type == "repayment"))

      assert repayment.source_id == transaction.id
      assert Decimal.equal?(repayment.amount, Decimal.new("-100.00"))

      reloaded = Lending.get_account!(scope, account.id)
      assert Decimal.equal?(repayment.running_balance, reloaded.outstanding_balance)
      assert Decimal.equal?(Accounting.rebuild_outstanding_balance(scope, account.id), reloaded.outstanding_balance)
    end

    test "recalculates the customer's current_balance after a payment" do
      application = approved_application_fixture()
      scope = %Scope{organisation_id: application.organisation_id}
      account = application.loan_account
      {:ok, _transaction} = payment_result(scope, account, account.outstanding_balance)

      reloaded_customer = Customers.get_customer!(scope, application.customer_id)
      assert Decimal.equal?(reloaded_customer.current_balance, Decimal.new("0.00"))
    end
  end

  describe "void_payment/2" do
    test "reverses the allocation, restores the balance, and reopens a closed account" do
      application = approved_application_fixture()
      scope = %Scope{organisation_id: application.organisation_id}
      account = application.loan_account
      {:ok, transaction} = payment_result(scope, account, account.outstanding_balance)
      admin = admin_fixture()

      assert Lending.get_account!(scope, account.id).status == "closed"

      assert {:ok, voided} =
               Payments.void_payment(transaction, %{"voided_by_id" => admin.id, "void_reason" => "Entered in error"})

      assert voided.status == "voided"

      reloaded_account = Lending.get_account!(scope, account.id)
      assert reloaded_account.status == "active"
      assert Decimal.equal?(reloaded_account.outstanding_balance, account.outstanding_balance)

      installments = Lending.list_installments_for_account(scope, account.id)
      assert Enum.all?(installments, &(&1.status != "paid"))
      assert Enum.all?(installments, &Decimal.equal?(&1.paid_amount, Decimal.new("0.00")))

      assert Decimal.equal?(Accounting.rebuild_outstanding_balance(scope, account.id), reloaded_account.outstanding_balance)
    end

    test "does not touch an already-voided transaction's status via a second void" do
      application = approved_application_fixture()
      scope = %Scope{organisation_id: application.organisation_id}
      account = application.loan_account
      {:ok, transaction} = payment_result(scope, account, "50.00")
      admin = admin_fixture()

      {:ok, voided} = Payments.void_payment(transaction, %{"voided_by_id" => admin.id, "void_reason" => "test"})
      assert voided.status == "voided"

      assert_raise FunctionClauseError, fn ->
        Payments.void_payment(voided, %{"voided_by_id" => admin.id, "void_reason" => "again"})
      end
    end
  end

  defp payment_result(scope, account, amount) do
    Payments.record_payment(scope, valid_payment_attrs(account, %{"amount" => amount}))
  end
end
