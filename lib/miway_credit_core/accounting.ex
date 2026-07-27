defmodule MiwayCreditCore.Accounting do
  @moduledoc """
  The ledger — the single source of truth for what a `LoanAccount`
  owes. `Accounting.AccountingEntry` rows are immutable and insert-only;
  every operation that changes a balance (disbursement in
  `Applications`, repayment/reversal in `Payments`, write-off in
  `Lending.Servicing`) posts one inside the same `Ecto.Multi` that
  updates the account's cached `outstanding_balance` — no update
  function is exposed here, so entries can't drift once written.

  Single import site for ledger reads (`alias MiwayCreditCore.Accounting`).
  """

  alias MiwayCreditCore.Accounting.Ledger

  defdelegate list_entries_for_account(scope, loan_account_id), to: Ledger
  defdelegate rebuild_outstanding_balance(scope, loan_account_id), to: Ledger
end
