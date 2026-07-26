defmodule MiwayCreditCore.Loans do
  @moduledoc """
  Public facade over the loan domain. The domain is split into five
  bounded concepts — application, account, schedule, payment
  transaction, and accounting ledger (see
  `docs/MIWAY_CREDITCORE_CONSTITUTION.md`) — each implemented in its own
  submodule; this module just re-exposes their functions under one
  familiar import site (`alias MiwayCreditCore.Loans`).
  """

  import Ecto.Query
  alias MiwayCreditCore.Repo
  alias MiwayCreditCore.Loans.{Applications, Servicing, Schedule, Payments, Ledger, Collateral,
                               InterestCalculator}

  # ---------------------------------------------------------------------------
  # Applications
  # ---------------------------------------------------------------------------

  defdelegate list_applications(opts \\ []), to: Applications
  defdelegate get_applications_for_customer(customer_id), to: Applications
  defdelegate get_application!(id), to: Applications
  defdelegate create_application(attrs \\ %{}), to: Applications
  defdelegate update_application(application, attrs), to: Applications
  defdelegate delete_application(application), to: Applications
  defdelegate approve_application(application, admin_id), to: Applications
  defdelegate reject_application(application, admin_id, reason), to: Applications
  defdelegate fraud_signals(application), to: Applications
  defdelegate count_applications(), to: Applications
  defdelegate count_active_applications(), to: Applications

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

  # ---------------------------------------------------------------------------
  # Payments
  # ---------------------------------------------------------------------------

  defdelegate list_transactions_for_account(loan_account_id), to: Payments
  defdelegate get_transaction!(id), to: Payments
  defdelegate record_payment(attrs \\ %{}), to: Payments
  defdelegate void_payment(transaction, attrs), to: Payments

  # ---------------------------------------------------------------------------
  # Ledger
  # ---------------------------------------------------------------------------

  defdelegate list_entries_for_account(loan_account_id), to: Ledger
  defdelegate rebuild_outstanding_balance(loan_account_id), to: Ledger

  # ---------------------------------------------------------------------------
  # Collateral — attaches only to an approved LoanAccount
  # ---------------------------------------------------------------------------

  def list_collaterals_for_account(loan_account_id) do
    Collateral
    |> where([c], c.loan_account_id == ^loan_account_id)
    |> order_by([c], asc: c.inserted_at)
    |> Repo.all()
  end

  def get_collateral!(id), do: Repo.get!(Collateral, id)

  def create_collateral(attrs \\ %{}) do
    %Collateral{}
    |> Collateral.changeset(attrs)
    |> Repo.insert()
  end

  def delete_collateral(%Collateral{} = collateral), do: Repo.delete(collateral)

  def total_collateral_value(loan_account_id) do
    from(c in Collateral,
      where: c.loan_account_id == ^loan_account_id,
      select: coalesce(sum(c.estimated_value), ^Decimal.new("0.00"))
    )
    |> Repo.one()
  end
end
