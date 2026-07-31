defmodule MiwayCreditCore.Lending.Schedule do
  @moduledoc """
  Read access to the repayment plan, plus the arrears sweep. Rows here
  are never touched by money-received logic directly — only by
  `mark_overdue_installments/0` (time-based) and payment allocation
  (money-based, see `MiwayCreditCore.Payments`).
  """

  import Ecto.Query
  alias MiwayCreditCore.Repo
  alias MiwayCreditCore.Lending.{RepaymentScheduleInstallment, LoanAccount}
  alias MiwayCreditCore.Accounting.{AccountingEntry, GeneralLedger}
  alias MiwayCreditCore.Collections
  alias MiwayCreditCore.Accounts.Scope

  def list_installments_for_account(%Scope{} = scope, loan_account_id) do
    RepaymentScheduleInstallment
    |> scope_organisation(scope)
    |> where([i], i.loan_account_id == ^loan_account_id)
    |> order_by([i], asc: i.installment_number)
    |> Repo.all()
  end

  def get_installment!(%Scope{} = scope, id) do
    RepaymentScheduleInstallment
    |> scope_organisation(scope)
    |> Repo.get!(id)
  end

  @doc "Earliest unpaid installment due for a customer, ordered by due_date, loan_account preloaded."
  def get_upcoming_installments(%Scope{} = scope, customer_id) do
    RepaymentScheduleInstallment
    |> scope_organisation(scope)
    |> join(:inner, [i], a in assoc(i, :loan_account))
    |> where([i, a], a.customer_id == ^customer_id)
    |> where([i], i.status in ["upcoming", "overdue", "partially_paid"])
    |> order_by([i], asc: i.due_date)
    |> preload(:loan_account)
    |> Repo.all()
  end

  @doc """
  Flips every unpaid installment whose due_date has passed to
  "overdue", across every organisation — this is a system-wide batch
  job (called periodically by MiwayCreditCore.ArrearsScheduler), not a
  request handler, so it deliberately has no scope. Returns the number
  of rows flipped.

  Also accrues a one-time late payment penalty (the loan product's
  late_payment_penalty_percent against what's still owed on that
  installment) the moment an installment goes overdue — not a daily
  or compounding charge, just the single accrual real loan products
  actually apply, folded into the account's outstanding_balance and
  posted as a "penalty" AccountingEntry, same pattern as the
  origination fee posted at disbursement. Also ensures a
  `Collections.CollectionCase` is open for the account — collections
  work starts the moment arrears exist, not behind some extra
  severity threshold.
  """
  def mark_overdue_installments do
    today = Date.utc_today()

    newly_overdue =
      from(i in RepaymentScheduleInstallment,
        where: i.status in ["upcoming", "partially_paid"] and i.due_date < ^today
      )
      |> preload(loan_account: :loan_product)
      |> Repo.all()

    Enum.each(newly_overdue, &flip_to_overdue/1)

    length(newly_overdue)
  end

  defp flip_to_overdue(installment) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    account = installment.loan_account
    penalty = penalty_owed(installment, account.loan_product)

    Ecto.Multi.new()
    |> Ecto.Multi.update(
      :installment,
      RepaymentScheduleInstallment.changeset(installment, %{
        status: "overdue",
        penalty_amount: Decimal.add(installment.penalty_amount, penalty)
      })
    )
    |> maybe_accrue_penalty_ledger(account, penalty, now)
    |> Ecto.Multi.run(:collection_case, fn repo, _changes ->
      Collections.ensure_case_opened(repo, account)
    end)
    |> Repo.transaction()
  end

  defp penalty_owed(installment, product) do
    outstanding = Decimal.sub(installment.scheduled_amount, installment.paid_amount)

    outstanding
    |> Decimal.mult(product.late_payment_penalty_percent)
    |> Decimal.div(Decimal.new("100"))
    |> Decimal.round(2)
  end

  # Zero-penalty products skip this entirely rather than posting a
  # $0.00 no-op ledger entry — same convention as the origination fee.
  defp maybe_accrue_penalty_ledger(multi, account, penalty, now) do
    if Decimal.compare(penalty, Decimal.new("0")) == :gt do
      multi
      |> Ecto.Multi.update(
        :account,
        LoanAccount.changeset(account, %{
          outstanding_balance: Decimal.add(account.outstanding_balance, penalty)
        })
      )
      |> Ecto.Multi.insert(:penalty_entry, fn %{account: account} ->
        AccountingEntry.changeset(%AccountingEntry{}, %{
          organisation_id: account.organisation_id,
          loan_account_id: account.id,
          entry_type: "penalty",
          amount: penalty,
          running_balance: account.outstanding_balance,
          source_type: "loan_account",
          source_id: account.id,
          description: "Late payment penalty accrued",
          occurred_at: now
        })
      end)
      |> GeneralLedger.post_journal_entry(:penalty_gl, %{
        organisation_id: account.organisation_id,
        description: "Late payment penalty accrued",
        source_type: "loan_account",
        source_id: account.id,
        occurred_at: now,
        lines: [
          %{account_code: "1100", debit: penalty},
          %{account_code: "4200", credit: penalty}
        ]
      })
    else
      multi
    end
  end

  @doc "Count of overdue installments, optionally scoped to one customer."
  def count_overdue_installments(%Scope{} = scope, customer_id \\ nil) do
    RepaymentScheduleInstallment
    |> scope_organisation(scope)
    |> maybe_join_customer(customer_id)
    |> where([i], i.status == "overdue")
    |> Repo.aggregate(:count)
  end

  @doc "Total value of all overdue installments, optionally scoped to one customer."
  def total_overdue_amount(%Scope{} = scope, customer_id \\ nil) do
    RepaymentScheduleInstallment
    |> scope_organisation(scope)
    |> maybe_join_customer(customer_id)
    |> where([i], i.status == "overdue")
    |> select([i], coalesce(sum(i.scheduled_amount - i.paid_amount), ^Decimal.new("0.00")))
    |> Repo.one()
  end

  @doc "Overdue installments, oldest due_date first, loan_account + customer preloaded."
  def overdue_installments(%Scope{} = scope) do
    RepaymentScheduleInstallment
    |> scope_organisation(scope)
    |> where([i], i.status == "overdue")
    |> order_by([i], asc: i.due_date)
    |> preload(loan_account: :customer)
    |> Repo.all()
  end

  @doc "Days since the oldest overdue installment on this account fell due. 0 if none overdue."
  def days_past_due(%LoanAccount{id: loan_account_id}) do
    oldest_overdue_due_date =
      from(i in RepaymentScheduleInstallment,
        where: i.loan_account_id == ^loan_account_id and i.status == "overdue",
        order_by: [asc: i.due_date],
        select: i.due_date,
        limit: 1
      )
      |> Repo.one()

    case oldest_overdue_due_date do
      nil -> 0
      due_date -> Date.diff(Date.utc_today(), due_date)
    end
  end

  @doc "Installments due within the next `days` days (default 7), scoped to the caller's organisation."
  def installments_due_soon(%Scope{} = scope, days \\ 7) do
    today = Date.utc_today()
    cutoff = Date.add(today, days)

    RepaymentScheduleInstallment
    |> scope_organisation(scope)
    |> where(
      [i],
      i.status in ["upcoming", "partially_paid"] and i.due_date >= ^today and
        i.due_date <= ^cutoff
    )
    |> order_by([i], asc: i.due_date)
    |> preload(loan_account: :customer)
    |> Repo.all()
  end

  defp scope_organisation(query, %Scope{organisation_id: :all}), do: query

  defp scope_organisation(query, %Scope{organisation_id: organisation_id}) do
    where(query, organisation_id: ^organisation_id)
  end

  defp maybe_join_customer(query, nil), do: query

  defp maybe_join_customer(query, customer_id) do
    query
    |> join(:inner, [i], a in assoc(i, :loan_account))
    |> where([i, a], a.customer_id == ^customer_id)
  end
end
