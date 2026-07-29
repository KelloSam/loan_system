defmodule MiwayCreditCore.Payments do
  @moduledoc """
  Money actually received. `record_payment/2` allocates the *payable*
  portion of the amount (capped at the account's outstanding_balance)
  across that account's unpaid installments, in the organisation's
  configured order (penalty, then interest, then principal by
  default — see `MiwayCreditCore.Organisations.get_settings/1`), posts a
  repayment ledger entry, and updates the account's cached balance —
  all in one transaction. Overpaying is allowed: the unapplied excess
  is recorded as `overpayment_amount` on the transaction itself rather
  than silently rejected or turned into a customer credit wallet.

  Never hard-deletes a transaction — a posted payment that was a
  mistake is voided (`void_payment/2`); a posted payment that later
  turns out not to have cleared (a bounced cheque) is failed
  (`fail_payment/2`); a payment attempt that never reconciled in the
  first place is logged directly as failed
  (`record_failed_payment/2`), with no allocation or balance effect.
  """

  import Ecto.Query
  alias MiwayCreditCore.Repo
  alias MiwayCreditCore.Organisations
  alias MiwayCreditCore.Customers.CustomerStats
  alias MiwayCreditCore.Payments.{PaymentTransaction, PaymentAllocation}
  alias MiwayCreditCore.Lending.{LoanAccount, RepaymentScheduleInstallment}
  alias MiwayCreditCore.Accounting.{AccountingEntry, GeneralLedger}
  alias MiwayCreditCore.Accounts.Scope

  @default_allocation_order ~w(penalty interest principal)

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
  Records a payment: inserts the transaction, allocates the payable
  portion across unpaid installments in the organisation's configured
  order, posts a repayment ledger entry, and updates the account's
  cached outstanding_balance (closing the account if it reaches
  zero). Any amount beyond the outstanding balance is recorded as
  `overpayment_amount` — never applied, never rejected.

  Looks the account up itself, scoped — loan_account_id comes from
  submitted form/API params, not a value the caller already had
  scope-verified, so this can't be used to record a payment against
  another organisation's account by submitting a foreign id directly.
  """
  def record_payment(%Scope{} = scope, attrs \\ %{}) do
    loan_account_id  = Map.get(attrs, :loan_account_id) || Map.get(attrs, "loan_account_id")
    idempotency_key  = Map.get(attrs, :idempotency_key) || Map.get(attrs, "idempotency_key")
    amount           = decimal(Map.get(attrs, :amount) || Map.get(attrs, "amount"))
    account          = loan_account_id && get_scoped_account(scope, loan_account_id)
    payable          = account && amount && decimal_min(amount, account.outstanding_balance)
    overpayment      = payable && Decimal.sub(amount, payable)

    existing =
      loan_account_id && idempotency_key &&
        find_by_idempotency_key(scope, loan_account_id, idempotency_key)

    if existing do
      {:ok, existing}
    else
      do_record_payment(attrs, account, payable, overpayment)
    end
  end

  defp find_by_idempotency_key(%Scope{} = scope, loan_account_id, idempotency_key) do
    PaymentTransaction
    |> scope_organisation(scope)
    |> where([t], t.loan_account_id == ^loan_account_id and t.idempotency_key == ^idempotency_key)
    |> Repo.one()
  end

  defp do_record_payment(attrs, account, payable, overpayment) do
    attrs =
      attrs
      |> stringify_keys()
      |> Map.put("organisation_id", account && account.organisation_id)
      |> Map.put("payable_amount", payable)
      |> Map.put("overpayment_amount", overpayment)

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:transaction, PaymentTransaction.changeset(%PaymentTransaction{}, attrs))
    |> Ecto.Multi.run(:allocations, fn repo, %{transaction: transaction} ->
      allocate(repo, account, transaction, transaction.payable_amount)
    end)
    |> Ecto.Multi.run(:account, fn repo, %{transaction: transaction} ->
      new_balance = Decimal.sub(account.outstanding_balance, transaction.payable_amount)
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
        amount: Decimal.negate(transaction.payable_amount),
        running_balance: account.outstanding_balance,
        source_type: "payment_transaction",
        source_id: transaction.id,
        description: "Payment received",
        recorded_by_id: transaction.recorded_by_id,
        occurred_at: now
      })
    end)
    |> Ecto.Multi.merge(fn %{transaction: transaction, account: account} ->
      GeneralLedger.post_journal_entry(Ecto.Multi.new(), :repayment_gl, %{
        organisation_id: account.organisation_id,
        description: "Payment received",
        source_type: "payment_transaction",
        source_id: transaction.id,
        occurred_at: now,
        recorded_by_id: transaction.recorded_by_id,
        lines: [
          %{account_code: GeneralLedger.cash_account_code(transaction.method), debit: transaction.payable_amount},
          %{account_code: "1100", credit: transaction.payable_amount}
        ]
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

  @doc """
  Logs a payment attempt that never actually reconciled (the customer
  says they paid, but no matching funds arrived) — a `"failed"`
  transaction with no allocation, no ledger entry, and no balance
  effect. Purely an auditable record of the attempt.
  """
  def record_failed_payment(%Scope{} = scope, attrs \\ %{}) do
    loan_account_id = Map.get(attrs, :loan_account_id) || Map.get(attrs, "loan_account_id")
    account          = loan_account_id && get_scoped_account(scope, loan_account_id)

    attrs =
      attrs
      |> stringify_keys()
      |> Map.put("organisation_id", account && account.organisation_id)

    %PaymentTransaction{}
    |> PaymentTransaction.failed_attempt_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Voids a posted payment: reverses its allocations' effect on each
  installment's paid_amount/penalty_paid/status, posts a compensating
  reversal ledger entry, restores the account's outstanding_balance
  (reopening it if voiding pushes the balance back above zero), and
  recalculates customer stats. Never deletes the transaction row — the
  audit trail stays intact.
  """
  def void_payment(%PaymentTransaction{status: "posted"} = transaction, attrs) do
    reverse_posted_transaction(transaction, attrs, %{
      status: "voided",
      timestamp_field: "voided_at",
      actor_field: "voided_by_id",
      reason_field: "void_reason",
      changeset_fun: &PaymentTransaction.void_changeset/2,
      description: "Payment voided"
    })
  end

  @doc """
  Marks a *posted* payment as failed after the fact — a cheque that
  bounced days after being recorded, for example. Same reversal
  mechanics as `void_payment/2` (nothing is deleted, the balance and
  installments are restored), but lands on `"failed"` with a
  `fail_reason` rather than `"voided"` with a `void_reason`, so
  reporting can later tell "we made a mistake" apart from "the
  customer's payment didn't clear".
  """
  def fail_payment(%PaymentTransaction{status: "posted"} = transaction, attrs) do
    reverse_posted_transaction(transaction, attrs, %{
      status: "failed",
      timestamp_field: "failed_at",
      actor_field: "failed_by_id",
      reason_field: "fail_reason",
      changeset_fun: &PaymentTransaction.fail_changeset/2,
      description: "Payment failed"
    })
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Shared by void_payment/2 and fail_payment/2 — both un-post a
  # payment the exact same way (reverse allocations, restore the
  # account balance and installments, post a compensating reversal
  # entry, recalculate customer stats); they differ only in which
  # terminal status/timestamp/actor/reason fields get set.
  defp reverse_posted_transaction(transaction, attrs, opts) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    account = Repo.get!(LoanAccount, transaction.loan_account_id)
    attrs = stringify_keys(attrs)

    Ecto.Multi.new()
    |> Ecto.Multi.update(:transaction, opts.changeset_fun.(transaction, Map.merge(attrs, %{
      "status" => opts.status,
      opts.timestamp_field => now
    })))
    |> Ecto.Multi.run(:reversed_installments, fn repo, _ ->
      reverse_allocations(repo, transaction)
    end)
    |> Ecto.Multi.run(:account, fn repo, _ ->
      restored = transaction.payable_amount || transaction.amount
      new_balance = Decimal.add(account.outstanding_balance, restored)
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
        amount: transaction.payable_amount || transaction.amount,
        running_balance: account.outstanding_balance,
        source_type: "payment_transaction",
        source_id: transaction.id,
        description: "#{opts.description}: #{Map.get(attrs, opts.reason_field)}",
        recorded_by_id: Map.get(attrs, opts.actor_field),
        occurred_at: now
      })
    end)
    |> GeneralLedger.post_reversal(:reversal_gl, %{
      organisation_id: account.organisation_id,
      description: "#{opts.description}: #{Map.get(attrs, opts.reason_field)}",
      source_type: "payment_transaction",
      source_id: transaction.id,
      occurred_at: now,
      recorded_by_id: Map.get(attrs, opts.actor_field)
    })
    |> Ecto.Multi.run(:update_customer_stats, fn repo, %{account: account} ->
      CustomerStats.recalculate(repo, account.customer_id)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{transaction: transaction}} -> {:ok, transaction}
      {:error, _, reason, _} -> {:error, reason}
    end
  end

  # Allocates `payable` across unpaid/overdue installments, oldest
  # due-date-first, walking the organisation's configured component
  # order (default penalty -> interest -> principal). Interest and
  # principal still share a single paid_amount column — which portion
  # of it is "interest" vs "principal" is derived on the fly
  # (interest-first, the standard amortization convention), not stored
  # separately, so this never double-counts across passes.
  defp allocate(repo, %LoanAccount{} = account, transaction, payable) do
    installments =
      from(i in RepaymentScheduleInstallment,
        where: i.loan_account_id == ^account.id and i.status in ["upcoming", "overdue", "partially_paid"],
        order_by: [asc: i.due_date]
      )
      |> repo.all()

    order = allocation_order(account.organisation_id)

    Enum.reduce_while(installments, payable, fn installment, remaining ->
      if Decimal.compare(remaining, Decimal.new("0")) == :eq do
        {:halt, remaining}
      else
        {:cont, allocate_installment(repo, order, installment, account, transaction, remaining)}
      end
    end)

    {:ok, :allocated}
  end

  # Fully settles one installment — walking its components in the
  # organisation's configured order — before any remaining payment
  # moves on to the next (oldest-due-date) installment. Nested this
  # way rather than component-first-across-every-installment so a
  # payment can never skip ahead to pay off, say, installment #3's
  # interest while installment #1's principal is still outstanding.
  defp allocate_installment(repo, order, installment, account, transaction, remaining) do
    {remaining, paid_amount, penalty_paid} =
      Enum.reduce(order, {remaining, installment.paid_amount, installment.penalty_paid}, fn
        component, {remaining, paid_amount, penalty_paid} ->
          if Decimal.compare(remaining, Decimal.new("0")) == :eq do
            {remaining, paid_amount, penalty_paid}
          else
            current = %{paid_amount: paid_amount, penalty_paid: penalty_paid}
            owed = component_owed(component, installment, current)

            if Decimal.compare(owed, Decimal.new("0")) == :gt do
              take = decimal_min(remaining, owed)

              %PaymentAllocation{}
              |> PaymentAllocation.changeset(%{
                organisation_id: account.organisation_id,
                payment_transaction_id: transaction.id,
                repayment_schedule_installment_id: installment.id,
                allocated_amount: take,
                component: component
              })
              |> repo.insert!()

              updated = apply_component(component, current, take)
              {Decimal.sub(remaining, take), updated.paid_amount, updated.penalty_paid}
            else
              {remaining, paid_amount, penalty_paid}
            end
          end
      end)

    fully_paid? =
      Decimal.compare(paid_amount, installment.scheduled_amount) != :lt and
        Decimal.compare(penalty_paid, installment.penalty_amount) != :lt

    # "partially_paid" describes progress against principal/interest
    # specifically — an installment where only the penalty got paid
    # (paid_amount untouched) hasn't made any repayment progress, so
    # its status is left as-is rather than misleadingly flipping.
    status =
      cond do
        fully_paid? -> "paid"
        Decimal.compare(paid_amount, Decimal.new("0")) == :gt -> "partially_paid"
        true -> installment.status
      end

    installment
    |> RepaymentScheduleInstallment.changeset(%{
      paid_amount: paid_amount,
      penalty_paid: penalty_paid,
      status: status,
      paid_at: if(fully_paid?, do: DateTime.utc_now() |> DateTime.truncate(:second), else: nil)
    })
    |> repo.update!()

    remaining
  end

  defp component_owed("penalty", installment, current) do
    Decimal.sub(installment.penalty_amount, current.penalty_paid)
  end

  defp component_owed("interest", installment, current) do
    paid_interest = decimal_min(current.paid_amount, installment.scheduled_interest)
    Decimal.sub(installment.scheduled_interest, paid_interest)
  end

  defp component_owed("principal", installment, current) do
    paid_interest = decimal_min(current.paid_amount, installment.scheduled_interest)
    paid_principal = Decimal.sub(current.paid_amount, paid_interest)
    Decimal.sub(installment.scheduled_principal, paid_principal)
  end

  defp apply_component("penalty", current, take), do: %{current | penalty_paid: Decimal.add(current.penalty_paid, take)}
  defp apply_component(_interest_or_principal, current, take), do: %{current | paid_amount: Decimal.add(current.paid_amount, take)}

  defp allocation_order(organisation_id) do
    case Organisations.get_settings(organisation_id) do
      %{allocation_order: [_ | _] = order} -> order
      _ -> @default_allocation_order
    end
  end

  # Reverses every allocation this transaction made, restoring each
  # touched installment's paid_amount/penalty_paid/status. Grouped by
  # installment first — a single transaction can carry more than one
  # allocation against the same installment (e.g. a penalty allocation
  # and a principal allocation both landing on the same installment),
  # so each installment's reversal must apply in one pass, not
  # re-fetch-and-overwrite per allocation.
  defp reverse_allocations(repo, transaction) do
    today = Date.utc_today()

    from(pa in PaymentAllocation, where: pa.payment_transaction_id == ^transaction.id)
    |> repo.all()
    |> Enum.group_by(& &1.repayment_schedule_installment_id)
    |> Enum.each(fn {installment_id, allocations} ->
      installment = repo.get!(RepaymentScheduleInstallment, installment_id)

      {new_paid, new_penalty_paid} =
        Enum.reduce(allocations, {installment.paid_amount, installment.penalty_paid}, fn allocation, {paid, penalty_paid} ->
          case allocation.component do
            "penalty" -> {paid, Decimal.sub(penalty_paid, allocation.allocated_amount)}
            _ -> {Decimal.sub(paid, allocation.allocated_amount), penalty_paid}
          end
        end)

      status =
        cond do
          Decimal.compare(new_paid, Decimal.new("0")) == :gt -> "partially_paid"
          Date.compare(installment.due_date, today) == :lt -> "overdue"
          true -> "upcoming"
        end

      installment
      |> RepaymentScheduleInstallment.changeset(%{
        paid_amount: new_paid,
        penalty_paid: new_penalty_paid,
        status: status,
        paid_at: nil
      })
      |> repo.update!()
    end)

    {:ok, :reversed}
  end

  defp decimal_min(a, b), do: if(Decimal.compare(a, b) == :gt, do: b, else: a)

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
