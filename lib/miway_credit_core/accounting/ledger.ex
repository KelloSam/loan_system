defmodule MiwayCreditCore.Accounting.Ledger do
  @moduledoc """
  Read access to the accounting ledger. Entries are inserted inline by
  whichever operation causes them (disbursement in `Applications`,
  repayment/reversal in `Payments`, write-off in `Servicing`) as part of
  the same `Ecto.Multi` that updates the account's cached
  `outstanding_balance` — no update function is exposed here or
  anywhere else, so entries are immutable once written.
  """

  import Ecto.Query
  alias MiwayCreditCore.Repo
  alias MiwayCreditCore.Accounting.AccountingEntry

  def list_entries_for_account(loan_account_id) do
    AccountingEntry
    |> where([e], e.loan_account_id == ^loan_account_id)
    |> order_by([e], asc: e.inserted_at)
    |> Repo.all()
  end

  @doc """
  Sums every ledger entry for an account and returns the resulting
  balance — the ground truth `outstanding_balance` should always equal.
  An admin recovery/verification tool: since the cache is only ever
  written alongside a ledger insert in the same transaction, the two
  should never diverge under normal operation, but this makes that
  claim checkable (and tests assert on it after every operation).
  """
  def rebuild_outstanding_balance(loan_account_id) do
    from(e in AccountingEntry,
      where: e.loan_account_id == ^loan_account_id,
      select: coalesce(sum(e.amount), ^Decimal.new("0.00"))
    )
    |> Repo.one()
  end
end
