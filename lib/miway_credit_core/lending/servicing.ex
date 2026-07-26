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
  alias MiwayCreditCore.Loans.CustomerStats
  alias MiwayCreditCore.Lending.LoanAccount
  alias MiwayCreditCore.Accounting.AccountingEntry

  def get_account!(id) do
    LoanAccount
    |> Repo.get!(id)
    |> Repo.preload([:loan_application, :customer])
  end

  def list_accounts_for_customer(customer_id) do
    LoanAccount
    |> where([a], a.customer_id == ^customer_id)
    |> order_by([a], desc: a.inserted_at)
    |> preload(:repayment_schedule_installments)
    |> Repo.all()
  end

  def count_active_accounts do
    from(a in LoanAccount, where: a.status == "active")
    |> Repo.aggregate(:count)
  end

  def total_outstanding_balance do
    from(a in LoanAccount,
      where: a.status == "active",
      select: coalesce(sum(a.outstanding_balance), ^Decimal.new("0.00"))
    )
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
      loan_account_id: account.id,
      entry_type: "write_off",
      amount: Decimal.negate(account.outstanding_balance),
      running_balance: Decimal.new("0.00"),
      source_type: "manual_adjustment",
      description: "Balance written off",
      recorded_by_id: admin_id,
      occurred_at: now
    }))
    |> Ecto.Multi.run(:update_customer_stats, fn repo, %{account: account} ->
      CustomerStats.recalculate(repo, account.customer_id)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{account: account}}    -> {:ok, account}
      {:error, _, reason, _}        -> {:error, reason}
    end
  end
end
