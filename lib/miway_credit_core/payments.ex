defmodule MiwayCreditCore.Payments do
  @moduledoc """
  Money actually received. `record_payment/1` allocates the amount
  across that account's unpaid installments oldest-due-date-first (a
  transaction can satisfy more than one installment; an installment can
  be satisfied across more than one transaction), posts a repayment
  ledger entry, and updates the account's cached balance — all in one
  transaction. Overpayment (amount > outstanding_balance) is rejected
  rather than creating a credit balance.

  Never hard-deletes a transaction — see `void_payment/2`.
  """

  import Ecto.Query
  alias MiwayCreditCore.Repo
  alias MiwayCreditCore.Customers.CustomerStats
  alias MiwayCreditCore.Payments.{PaymentTransaction, PaymentAllocation}
  alias MiwayCreditCore.Lending.{LoanAccount, RepaymentScheduleInstallment}
  alias MiwayCreditCore.Accounting.AccountingEntry
  alias MiwayCreditCore.Accounts.Scope

  def list_transactions_for_account(%Scope{} = scope, loan_account_id) do
    PaymentTransaction
    |> scope_organisation(scope)
    |> where([t], t.loan_account_id == ^loan_account_id)
    |> order_by([t], desc: t.received_at)
    |> Repo.all()
  end

  def get_transaction!(%Scope{} = scope, id) do
    PaymentTransaction
    |> scope_organisation(scope)
    |> Repo.get!(id)
  end

  @doc """
  Records a payment: inserts the transaction, allocates it across
  unpaid installments oldest-first, posts a repayment ledger entry, and
  updates the account's cached outstanding_balance (closing the account
  if it reaches zero).

  Looks the account up itself, scoped — loan_account_id comes from
  submitted form/API params, not a value the caller already had
  scope-verified, so this can't be used to record a payment against
  another organisation's account by submitting a foreign id directly.
  """
  def record_payment(%Scope{} = scope, attrs \\ %{}) do
    loan_account_id = Map.get(attrs, :loan_account_id) || Map.get(attrs, "loan_account_id")
    amount           = decimal(Map.get(attrs, :amount) || Map.get(attrs, "amount"))
    account          = loan_account_id && get_scoped_account(scope, loan_account_id)
    attrs            = attrs |> stringify_keys() |> Map.put("organisation_id", account && account.organisation_id)

    with :ok <- check_amount(account, amount) do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      Ecto.Multi.new()
      |> Ecto.Multi.insert(:transaction, PaymentTransaction.changeset(%PaymentTransaction{}, attrs))
      |> Ecto.Multi.run(:allocations, fn repo, %{transaction: transaction} ->
        allocate(repo, account, transaction, transaction.amount)
      end)
      |> Ecto.Multi.run(:account, fn repo, %{transaction: transaction} ->
        new_balance = Decimal.sub(account.outstanding_balance, transaction.amount)
        closed? = Decimal.compare(new_balance, Decimal.new("0")) == :eq

        account
        |> LoanAccount.changeset(%{
          outstanding_balance: new_balance,
          status: if(closed?, do: "closed", else: account.status),
          closed_at: if(closed?, do: now, else: account.closed_at)
        })
        |> repo.update()
      end)
      |> Ecto.Multi.insert(:ledger_entry, fn %{transaction: transaction, account: account} ->
        AccountingEntry.changeset(%AccountingEntry{}, %{
          organisation_id: account.organisation_id,
          loan_account_id: account.id,
          entry_type: "repayment",
          amount: Decimal.negate(transaction.amount),
          running_balance: account.outstanding_balance,
          source_type: "payment_transaction",
          source_id: transaction.id,
          description: "Payment received",
          recorded_by_id: transaction.recorded_by_id,
          occurred_at: now
        })
      end)
      |> Ecto.Multi.run(:update_customer_stats, fn repo, %{account: account} ->
        CustomerStats.recalculate(repo, account.customer_id)
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{transaction: transaction}} -> {:ok, transaction}
        {:error, :transaction, changeset, _} -> {:error, changeset}
        {:error, _, reason, _} -> {:error, reason}
      end
    end
  end

  @doc """
  Voids a posted payment: reverses its allocations' effect on each
  installment's paid_amount/status, posts a compensating reversal
  ledger entry, restores the account's outstanding_balance (reopening
  it if voiding pushes the balance back above zero), and recalculates
  customer stats. Never deletes the transaction row — the audit trail
  stays intact.
  """
  def void_payment(%PaymentTransaction{status: "posted"} = transaction, attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    account = Repo.get!(LoanAccount, transaction.loan_account_id)
    attrs = stringify_keys(attrs)

    Ecto.Multi.new()
    |> Ecto.Multi.update(:transaction, PaymentTransaction.void_changeset(transaction, Map.merge(attrs, %{
      "status" => "voided",
      "voided_at" => now
    })))
    |> Ecto.Multi.run(:reversed_installments, fn repo, _ ->
      reverse_allocations(repo, transaction)
    end)
    |> Ecto.Multi.run(:account, fn repo, _ ->
      new_balance = Decimal.add(account.outstanding_balance, transaction.amount)
      reopen? = account.status == "closed" and Decimal.compare(new_balance, Decimal.new("0")) == :gt

      account
      |> LoanAccount.changeset(%{
        outstanding_balance: new_balance,
        status: if(reopen?, do: "active", else: account.status),
        closed_at: if(reopen?, do: nil, else: account.closed_at)
      })
      |> repo.update()
    end)
    |> Ecto.Multi.insert(:reversal_entry, fn %{account: account} ->
      AccountingEntry.changeset(%AccountingEntry{}, %{
        organisation_id: account.organisation_id,
        loan_account_id: account.id,
        entry_type: "reversal",
        amount: transaction.amount,
        running_balance: account.outstanding_balance,
        source_type: "payment_transaction",
        source_id: transaction.id,
        description: "Payment voided: #{Map.get(attrs, "void_reason")}",
        recorded_by_id: Map.get(attrs, "voided_by_id"),
        occurred_at: now
      })
    end)
    |> Ecto.Multi.run(:update_customer_stats, fn repo, %{account: account} ->
      CustomerStats.recalculate(repo, account.customer_id)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{transaction: transaction}} -> {:ok, transaction}
      {:error, _, reason, _} -> {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp check_amount(nil, _amount), do: :ok
  defp check_amount(_account, nil), do: :ok

  defp check_amount(%LoanAccount{outstanding_balance: balance}, amount) do
    if Decimal.compare(amount, balance) == :gt do
      {:error, :amount_exceeds_balance}
    else
      :ok
    end
  end

  # Oldest-due-date-first allocation across unpaid installments.
  defp allocate(repo, %LoanAccount{id: loan_account_id, organisation_id: organisation_id}, transaction, amount) do
    installments =
      from(i in RepaymentScheduleInstallment,
        where: i.loan_account_id == ^loan_account_id and i.status in ["upcoming", "overdue", "partially_paid"],
        order_by: [asc: i.due_date]
      )
      |> repo.all()

    Enum.reduce_while(installments, amount, fn installment, remaining ->
      if Decimal.compare(remaining, Decimal.new("0")) == :eq do
        {:halt, remaining}
      else
        due = Decimal.sub(installment.scheduled_amount, installment.paid_amount)
        take = if Decimal.compare(remaining, due) == :gt, do: due, else: remaining

        %PaymentAllocation{}
        |> PaymentAllocation.changeset(%{
          organisation_id: organisation_id,
          payment_transaction_id: transaction.id,
          repayment_schedule_installment_id: installment.id,
          allocated_amount: take
        })
        |> repo.insert!()

        new_paid = Decimal.add(installment.paid_amount, take)
        fully_paid? = Decimal.compare(new_paid, installment.scheduled_amount) != :lt

        installment
        |> RepaymentScheduleInstallment.changeset(%{
          paid_amount: new_paid,
          status: if(fully_paid?, do: "paid", else: "partially_paid"),
          paid_at: if(fully_paid?, do: DateTime.utc_now() |> DateTime.truncate(:second), else: nil)
        })
        |> repo.update!()

        {:cont, Decimal.sub(remaining, take)}
      end
    end)

    {:ok, :allocated}
  end

  # Reverses every allocation this transaction made, restoring each
  # touched installment's paid_amount/status.
  defp reverse_allocations(repo, transaction) do
    allocations =
      from(pa in PaymentAllocation, where: pa.payment_transaction_id == ^transaction.id)
      |> repo.all()

    today = Date.utc_today()

    Enum.each(allocations, fn allocation ->
      installment = repo.get!(RepaymentScheduleInstallment, allocation.repayment_schedule_installment_id)
      new_paid = Decimal.sub(installment.paid_amount, allocation.allocated_amount)

      status =
        cond do
          Decimal.compare(new_paid, Decimal.new("0")) == :gt -> "partially_paid"
          Date.compare(installment.due_date, today) == :lt -> "overdue"
          true -> "upcoming"
        end

      installment
      |> RepaymentScheduleInstallment.changeset(%{paid_amount: new_paid, status: status, paid_at: nil})
      |> repo.update!()
    end)

    {:ok, :reversed}
  end

  defp decimal(nil), do: nil
  defp decimal(%Decimal{} = d), do: d
  defp decimal(v), do: Decimal.new(to_string(v))

  # Ecto.Changeset.cast/3 rejects a map with mixed atom/string keys —
  # normalize so callers can pass either.
  defp stringify_keys(attrs) do
    Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
  end

  defp get_scoped_account(scope, loan_account_id) do
    LoanAccount
    |> scope_organisation(scope)
    |> Repo.get(loan_account_id)
  end

  defp scope_organisation(query, %Scope{organisation_id: :all}), do: query
  defp scope_organisation(query, %Scope{organisation_id: organisation_id}) do
    where(query, organisation_id: ^organisation_id)
  end
end
