defmodule MiwayCreditCore.Lending do
  @moduledoc """
  Owns the credit actually extended: the `LoanAccount` itself, its
  repayment schedule, compound interest, and servicing (closing,
  writing off). Created only as the side effect of an approved
  `LoanApplication` — see `MiwayCreditCore.Applications`, which
  still owns that one atomic transaction (account + schedule +
  disbursement entry together) rather than this module reaching back
  into Applications.

  Single import site for everything account/schedule-shaped
  (`alias MiwayCreditCore.Lending`); internally delegates to
  `Lending.Servicing`, `Lending.Schedule`, and `Lending.InterestCalculator`.
  """

  alias MiwayCreditCore.Lending.{Servicing, Schedule, InterestCalculator}

  # ---------------------------------------------------------------------------
  # Servicing (LoanAccount lifecycle)
  # ---------------------------------------------------------------------------

  defdelegate get_account!(scope, id), to: Servicing
  defdelegate list_accounts_for_customer(scope, customer_id), to: Servicing
  defdelegate close_account(account), to: Servicing
  defdelegate write_off_account(account, admin_id), to: Servicing
  defdelegate reverse_disbursement(account, admin_id, reason), to: Servicing
  defdelegate count_active_accounts(scope), to: Servicing
  defdelegate total_outstanding_balance(scope), to: Servicing

  @doc "Compound interest details for an account. See `InterestCalculator.calculate/1`."
  def compound_interest_details(%{principal_amount: amount, interest_rate: rate, term_months: term}) do
    InterestCalculator.calculate(%{amount: amount, interest_rate: rate, term_months: term})
  end

  # ---------------------------------------------------------------------------
  # Schedule
  # ---------------------------------------------------------------------------

  defdelegate list_installments_for_account(scope, loan_account_id), to: Schedule
  defdelegate get_installment!(scope, id), to: Schedule
  defdelegate get_upcoming_installments(scope, customer_id), to: Schedule
  defdelegate mark_overdue_installments(), to: Schedule
  defdelegate count_overdue_installments(scope, customer_id \\ nil), to: Schedule
  defdelegate total_overdue_amount(scope, customer_id \\ nil), to: Schedule
  defdelegate overdue_installments(scope), to: Schedule
  defdelegate installments_due_soon(scope, days \\ 7), to: Schedule
  defdelegate days_past_due(account), to: Schedule
end
