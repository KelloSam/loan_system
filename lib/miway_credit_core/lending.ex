defmodule MiwayCreditCore.Lending do
  @moduledoc """
  Owns the credit actually extended: the `LoanAccount` itself, its
  repayment schedule, compound interest, and servicing (closing,
  writing off). Created only as the side effect of an approved
  `LoanApplication` — see `MiwayCreditCore.Loans.Applications`, which
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

  defdelegate get_account!(id), to: Servicing
  defdelegate list_accounts_for_customer(customer_id), to: Servicing
  defdelegate close_account(account), to: Servicing
  defdelegate write_off_account(account, admin_id), to: Servicing
  defdelegate count_active_accounts(), to: Servicing
  defdelegate total_outstanding_balance(), to: Servicing

  @doc "Compound interest details for an account. See `InterestCalculator.calculate/1`."
  def compound_interest_details(%{principal_amount: amount, interest_rate: rate, term_months: term}) do
    InterestCalculator.calculate(%{amount: amount, interest_rate: rate, term_months: term})
  end

  # ---------------------------------------------------------------------------
  # Schedule
  # ---------------------------------------------------------------------------

  defdelegate list_installments_for_account(loan_account_id), to: Schedule
  defdelegate get_installment!(id), to: Schedule
  defdelegate get_upcoming_installments(customer_id), to: Schedule
  defdelegate mark_overdue_installments(), to: Schedule
  defdelegate count_overdue_installments(customer_id \\ nil), to: Schedule
  defdelegate total_overdue_amount(customer_id \\ nil), to: Schedule
  defdelegate overdue_installments(), to: Schedule
  defdelegate installments_due_soon(days \\ 7), to: Schedule
end
