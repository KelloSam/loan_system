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

  `Accounting.GeneralLedger` (Step 14) is the real double-entry general
  ledger sitting alongside this per-account subledger — chart of
  accounts, balanced journal entries/lines, `total_debits == total_credits`
  as a checkable invariant. Its write functions
  (`post_journal_entry/3`, `post_reversal/3`) are called directly by
  callers building an `Ecto.Multi`, same as `AccountingEntry` itself;
  only its read functions are delegated here.
  """

  alias MiwayCreditCore.Accounting.{Ledger, GeneralLedger}

  defdelegate list_entries_for_account(scope, loan_account_id), to: Ledger
  defdelegate rebuild_outstanding_balance(scope, loan_account_id), to: Ledger

  defdelegate trial_balance(scope), to: GeneralLedger
  defdelegate cash_position(scope), to: GeneralLedger
end
