defmodule MiwayCreditCore.Lending.Servicing do
  @moduledoc """
  LoanAccount lifecycle — everything about an already-approved loan
  except money movement (see Payments) and the schedule (see Schedule).
  Named Servicing (the industry term for managing a granted loan), not
  Accounts, to avoid any collision with the existing auth
  `MiwayCreditCore.Accounts` context.
  """

  import Ecto.Query
  alias MiwayCreditCore.Repo
  alias MiwayCreditCore.Customers.CustomerStats
  alias MiwayCreditCore.Lending.LoanAccount
  alias MiwayCreditCore.Accounting.{AccountingEntry, GeneralLedger}
  alias MiwayCreditCore.Payments.PaymentTransaction
  alias MiwayCreditCore.Accounts.Scope

  @doc "Fetches an account by id, scoped — one belonging to a different organisation raises the same NoResultsError as an unknown id."
  def get_account!(%Scope{} = scope, id) do
    LoanAccount
    |> scope_organisation(scope)
    |> Repo.get!(id)
    |> Repo.preload([:loan_application, :customer])
  end

  def list_accounts_for_customer(%Scope{} = scope, customer_id) do
    LoanAccount
    |> scope_organisation(scope)
    |> where([a], a.customer_id == ^customer_id)
    |> order_by([a], desc: a.inserted_at)
    |> preload(:repayment_schedule_installments)
    |> Repo.all()
  end

  def count_active_accounts(%Scope{} = scope) do
    LoanAccount
    |> scope_organisation(scope)
    |> where([a], a.status == "active")
    |> Repo.aggregate(:count)
  end

  def total_outstanding_balance(%Scope{} = scope) do
    LoanAccount
    |> scope_organisation(scope)
    |> where([a], a.status == "active")
    |> select([a], coalesce(sum(a.outstanding_balance), ^Decimal.new("0.00")))
    |> Repo.one()
  end

  @doc "Closes an account once its balance has reached zero."
  def close_account(%LoanAccount{} = account) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    account
    |> LoanAccount.changeset(%{status: "closed", closed_at: now})
    |> Repo.update()
  end

  @doc """
  Writes off the remaining balance of an account: zeroes
  outstanding_balance, posts a compensating `write_off` ledger entry,
  and recalculates the customer's stats — all in one transaction.
  """
  def write_off_account(%LoanAccount{} = account, admin_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Ecto.Multi.new()
    |> Ecto.Multi.update(:account, LoanAccount.changeset(account, %{
      status: "written_off",
      outstanding_balance: Decimal.new("0.00"),
      closed_at: now
    }))
    |> Ecto.Multi.insert(:entry, AccountingEntry.changeset(%AccountingEntry{}, %{
      organisation_id: account.organisation_id,
      loan_account_id: account.id,
      entry_type: "write_off",
      amount: Decimal.negate(account.outstanding_balance),
      running_balance: Decimal.new("0.00"),
      source_type: "manual_adjustment",
      description: "Balance written off",
      recorded_by_id: admin_id,
      occurred_at: now
    }))
    |> GeneralLedger.post_journal_entry(:write_off_gl, %{
      organisation_id: account.organisation_id,
      description: "Balance written off",
      source_type: "manual_adjustment",
      occurred_at: now,
      recorded_by_id: admin_id,
      lines: [
        %{account_code: "5000", debit: account.outstanding_balance},
        %{account_code: "1100", credit: account.outstanding_balance}
      ]
    })
    |> Ecto.Multi.run(:update_customer_stats, fn repo, %{account: account} ->
      CustomerStats.recalculate(repo, account.customer_id)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{account: account}}    -> {:ok, account}
      {:error, _, reason, _}        -> {:error, reason}
    end
  end

  @doc """
  Reverses a disbursement that was wrong from the start — zeroes
  outstanding_balance, posts a compensating `reversal` ledger entry,
  flips status to `"reversed"`, and recalculates the customer's stats
  — all in one transaction. The repayment schedule rows are left
  as-is, never deleted (same "append, never mutate" posture as the
  ledger itself) — a reversed account is simply excluded from
  `count_active_accounts/1`/`total_outstanding_balance/1`'s existing
  `status == "active"` filters, same as a written-off or closed one.

  Only possible before any real money has moved against the loan:
  refuses with `{:error, :payments_already_received}` once a posted
  payment exists — unwinding partial repayments too is a materially
  harder problem than this serves (a wrong disbursement caught before
  any repayment, the realistic case).
  """
  def reverse_disbursement(%LoanAccount{status: "active"} = account, admin_id, reason) do
    if Repo.exists?(from(t in PaymentTransaction, where: t.loan_account_id == ^account.id and t.status == "posted")) do
      {:error, :payments_already_received}
    else
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      Ecto.Multi.new()
      |> Ecto.Multi.update(:account, LoanAccount.changeset(account, %{
        status: "reversed",
        outstanding_balance: Decimal.new("0.00"),
        reversed_at: now,
        reversed_by_id: admin_id,
        reversal_reason: reason
      }))
      |> Ecto.Multi.insert(:entry, AccountingEntry.changeset(%AccountingEntry{}, %{
        organisation_id: account.organisation_id,
        loan_account_id: account.id,
        entry_type: "reversal",
        amount: Decimal.negate(account.outstanding_balance),
        running_balance: Decimal.new("0.00"),
        source_type: "manual_adjustment",
        description: "Disbursement reversed: #{reason}",
        recorded_by_id: admin_id,
        occurred_at: now
      }))
      |> GeneralLedger.post_reversal(:reversal_gl, %{
        organisation_id: account.organisation_id,
        description: "Disbursement reversed: #{reason}",
        source_type: "loan_account",
        source_id: account.id,
        occurred_at: now,
        recorded_by_id: admin_id
      })
      |> Ecto.Multi.run(:update_customer_stats, fn repo, %{account: account} ->
        CustomerStats.recalculate(repo, account.customer_id)
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{account: account}} -> {:ok, account}
        {:error, _, reason, _}     -> {:error, reason}
      end
    end
  end

  def reverse_disbursement(%LoanAccount{}, _admin_id, _reason), do: {:error, :invalid_status}

  defp scope_organisation(query, %Scope{organisation_id: :all}), do: query
  defp scope_organisation(query, %Scope{organisation_id: organisation_id}) do
    where(query, organisation_id: ^organisation_id)
  end
end
