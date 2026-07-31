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

      assert Decimal.equal?(
               reloaded.outstanding_balance,
               Decimal.sub(account.outstanding_balance, "234.56")
             )

      assert reloaded.status == "active"
      assert Accounting.trial_balance(scope).balanced?
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

      {:ok, transaction} =
        Payments.record_payment(scope, valid_payment_attrs(account, %{"amount" => partial}))

      first_reloaded = Lending.get_installment!(scope, first.id)
      assert first_reloaded.status == "partially_paid"
      assert Decimal.equal?(first_reloaded.paid_amount, partial)

      assert Lending.get_installment!(scope, second.id).status == "upcoming"
      assert Lending.get_installment!(scope, third.id).status == "upcoming"

      [allocation] =
        Accounting.list_entries_for_account(scope, account.id)
        |> Enum.filter(&(&1.source_id == transaction.id))

      assert Decimal.equal?(allocation.amount, Decimal.negate(partial))
    end

    test "a payment spanning more than one installment allocates across both" do
      application = approved_application_fixture(%{"requested_term_months" => "3"})
      scope = %Scope{organisation_id: application.organisation_id}
      account = application.loan_account
      [first, second, _third] = Lending.list_installments_for_account(scope, account.id)

      half_second = second.scheduled_amount |> Decimal.div(Decimal.new("2")) |> Decimal.round(2)
      amount = Decimal.add(first.scheduled_amount, half_second)

      {:ok, _transaction} =
        Payments.record_payment(scope, valid_payment_attrs(account, %{"amount" => amount}))

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

    test "an overpayment closes the account, applies only the balance, and records the excess" do
      application = approved_application_fixture()
      scope = %Scope{organisation_id: application.organisation_id}
      account = application.loan_account
      over = Decimal.add(account.outstanding_balance, Decimal.new("1.00"))

      assert {:ok, transaction} = payment_result(scope, account, over)
      assert Decimal.equal?(transaction.payable_amount, account.outstanding_balance)
      assert Decimal.equal?(transaction.overpayment_amount, Decimal.new("1.00"))

      reloaded = Lending.get_account!(scope, account.id)
      assert reloaded.status == "closed"
      assert Decimal.equal?(reloaded.outstanding_balance, Decimal.new("0.00"))

      assert Decimal.equal?(
               Accounting.rebuild_outstanding_balance(scope, account.id),
               Decimal.new("0.00")
             )
    end

    test "payroll_deduction is a valid method" do
      application = approved_application_fixture()
      scope = %Scope{organisation_id: application.organisation_id}
      account = application.loan_account

      assert {:ok, transaction} =
               Payments.record_payment(
                 scope,
                 valid_payment_attrs(account, %{"method" => "payroll_deduction"})
               )

      assert transaction.method == "payroll_deduction"
    end

    test "allocates penalty before interest and principal, even on a later installment" do
      application = approved_application_fixture(%{"requested_term_months" => "3"})
      scope = %Scope{organisation_id: application.organisation_id}
      account = application.loan_account
      [first, _second, _third] = Lending.list_installments_for_account(scope, account.id)

      # Manually accrue a penalty the way mark_overdue_installments/0 would,
      # without waiting on due dates — proves the allocator, not the scheduler.
      first
      |> MiwayCreditCore.Lending.RepaymentScheduleInstallment.changeset(%{penalty_amount: "10.00"})
      |> MiwayCreditCore.Repo.update!()

      partial = Decimal.new("10.00")

      {:ok, transaction} =
        Payments.record_payment(scope, valid_payment_attrs(account, %{"amount" => partial}))

      allocations =
        MiwayCreditCore.Repo.all(
          Ecto.Query.from(pa in MiwayCreditCore.Payments.PaymentAllocation,
            where: pa.payment_transaction_id == ^transaction.id
          )
        )

      assert [%{component: "penalty", allocated_amount: allocated}] = allocations
      assert Decimal.equal?(allocated, Decimal.new("10.00"))

      first_reloaded = Lending.get_installment!(scope, first.id)
      assert Decimal.equal?(first_reloaded.penalty_paid, Decimal.new("10.00"))
      assert Decimal.equal?(first_reloaded.paid_amount, Decimal.new("0.00"))
      assert first_reloaded.status == "upcoming"
    end

    test "respects a custom allocation_order (principal before interest)" do
      application = approved_application_fixture(%{"requested_term_months" => "3"})
      scope = %Scope{organisation_id: application.organisation_id}
      account = application.loan_account
      [first, _second, _third] = Lending.list_installments_for_account(scope, account.id)

      settings = MiwayCreditCore.Organisations.get_settings(account.organisation_id)

      settings
      |> MiwayCreditCore.Organisations.OrganisationSettings.changeset(%{
        allocation_order: ["principal", "interest"]
      })
      |> MiwayCreditCore.Repo.update!()

      small = Decimal.new("1.00")

      {:ok, transaction} =
        Payments.record_payment(scope, valid_payment_attrs(account, %{"amount" => small}))

      allocations =
        MiwayCreditCore.Repo.all(
          Ecto.Query.from(pa in MiwayCreditCore.Payments.PaymentAllocation,
            where: pa.payment_transaction_id == ^transaction.id
          )
        )

      assert [%{component: "principal"}] = allocations
      first_reloaded = Lending.get_installment!(scope, first.id)
      assert Decimal.equal?(first_reloaded.paid_amount, small)
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

      assert Decimal.equal?(
               Accounting.rebuild_outstanding_balance(scope, account.id),
               reloaded.outstanding_balance
             )
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
               Payments.void_payment(transaction, %{
                 "voided_by_id" => admin.id,
                 "void_reason" => "Entered in error"
               })

      assert voided.status == "voided"

      reloaded_account = Lending.get_account!(scope, account.id)
      assert reloaded_account.status == "active"
      assert Decimal.equal?(reloaded_account.outstanding_balance, account.outstanding_balance)

      installments = Lending.list_installments_for_account(scope, account.id)
      assert Enum.all?(installments, &(&1.status != "paid"))
      assert Enum.all?(installments, &Decimal.equal?(&1.paid_amount, Decimal.new("0.00")))

      assert Decimal.equal?(
               Accounting.rebuild_outstanding_balance(scope, account.id),
               reloaded_account.outstanding_balance
             )

      assert Accounting.trial_balance(scope).balanced?
    end

    test "does not touch an already-voided transaction's status via a second void" do
      application = approved_application_fixture()
      scope = %Scope{organisation_id: application.organisation_id}
      account = application.loan_account
      {:ok, transaction} = payment_result(scope, account, "50.00")
      admin = admin_fixture()

      {:ok, voided} =
        Payments.void_payment(transaction, %{"voided_by_id" => admin.id, "void_reason" => "test"})

      assert voided.status == "voided"

      assert_raise FunctionClauseError, fn ->
        Payments.void_payment(voided, %{"voided_by_id" => admin.id, "void_reason" => "again"})
      end
    end

    test "voiding an overpaid transaction restores only the payable_amount, not the full amount" do
      application = approved_application_fixture()
      scope = %Scope{organisation_id: application.organisation_id}
      account = application.loan_account
      over = Decimal.add(account.outstanding_balance, Decimal.new("1.00"))
      {:ok, transaction} = payment_result(scope, account, over)
      admin = admin_fixture()

      assert {:ok, _voided} =
               Payments.void_payment(transaction, %{
                 "voided_by_id" => admin.id,
                 "void_reason" => "test"
               })

      reloaded_account = Lending.get_account!(scope, account.id)
      assert Decimal.equal?(reloaded_account.outstanding_balance, account.outstanding_balance)
    end
  end

  describe "fail_payment/2" do
    test "reverses a posted payment exactly like void, but lands on failed with a fail_reason" do
      application = approved_application_fixture()
      scope = %Scope{organisation_id: application.organisation_id}
      account = application.loan_account
      {:ok, transaction} = payment_result(scope, account, account.outstanding_balance)
      admin = admin_fixture()

      assert Lending.get_account!(scope, account.id).status == "closed"

      assert {:ok, failed} =
               Payments.fail_payment(transaction, %{
                 "failed_by_id" => admin.id,
                 "fail_reason" => "Cheque bounced"
               })

      assert failed.status == "failed"
      assert failed.fail_reason == "Cheque bounced"
      assert failed.failed_at

      reloaded_account = Lending.get_account!(scope, account.id)
      assert reloaded_account.status == "active"
      assert Decimal.equal?(reloaded_account.outstanding_balance, account.outstanding_balance)
    end
  end

  describe "record_failed_payment/2" do
    test "logs a failed attempt with no allocation, ledger entry, or balance effect" do
      application = approved_application_fixture()
      scope = %Scope{organisation_id: application.organisation_id}
      account = application.loan_account
      recorder = admin_fixture()

      assert {:ok, transaction} =
               Payments.record_failed_payment(scope, %{
                 "loan_account_id" => account.id,
                 "amount" => "50.00",
                 "received_at" =>
                   DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
                 "method" => "mobile_money",
                 "recorded_by_id" => recorder.id,
                 "fail_reason" => "No matching funds received"
               })

      assert transaction.status == "failed"
      assert Decimal.equal?(transaction.payable_amount, Decimal.new("0.00"))

      reloaded_account = Lending.get_account!(scope, account.id)
      assert Decimal.equal?(reloaded_account.outstanding_balance, account.outstanding_balance)

      installments = Lending.list_installments_for_account(scope, account.id)
      assert Enum.all?(installments, &Decimal.equal?(&1.paid_amount, Decimal.new("0.00")))
    end
  end

  describe "record_payment/2 idempotency" do
    test "the same idempotency_key submitted twice returns the same transaction, not a duplicate" do
      application = approved_application_fixture()
      scope = %Scope{organisation_id: application.organisation_id}
      account = application.loan_account
      attrs = valid_payment_attrs(account, %{"idempotency_key" => "dup-key-1"})

      assert {:ok, first} = Payments.record_payment(scope, attrs)
      assert {:ok, second} = Payments.record_payment(scope, attrs)
      assert second.id == first.id

      assert Payments.list_transactions_for_account(scope, account.id) |> length() == 1
    end

    test "a different idempotency_key on the same account still creates a second transaction" do
      application = approved_application_fixture()
      scope = %Scope{organisation_id: application.organisation_id}
      account = application.loan_account

      assert {:ok, first} =
               Payments.record_payment(
                 scope,
                 valid_payment_attrs(account, %{"idempotency_key" => "key-a"})
               )

      assert {:ok, second} =
               Payments.record_payment(
                 scope,
                 valid_payment_attrs(account, %{"idempotency_key" => "key-b"})
               )

      assert first.id != second.id
      assert Payments.list_transactions_for_account(scope, account.id) |> length() == 2
    end

    test "no idempotency_key at all behaves exactly as before — every call inserts" do
      application = approved_application_fixture()
      scope = %Scope{organisation_id: application.organisation_id}
      account = application.loan_account

      assert {:ok, first} = payment_result(scope, account, "50.00")
      assert {:ok, second} = payment_result(scope, account, "50.00")

      assert first.id != second.id
      assert Payments.list_transactions_for_account(scope, account.id) |> length() == 2
    end
  end

  defp payment_result(scope, account, amount) do
    Payments.record_payment(scope, valid_payment_attrs(account, %{"amount" => amount}))
  end
end
