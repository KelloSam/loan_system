defmodule MiwayCreditCore.Loans do
  @moduledoc """
  Public facade over the loan-origination domain. Account/schedule
  concerns now live in `MiwayCreditCore.Lending` — this module
  delegates to it rather than owning that logic, and is being wound
  down in favor of callers using `Applications`/`Lending`/`Payments`
  directly (see `docs/architecture/context_boundaries.md`).
  """

  import Ecto.Query
  alias MiwayCreditCore.Repo
  alias MiwayCreditCore.{Lending, Accounting}
  alias MiwayCreditCore.Loans.{Applications, Payments, Collateral}

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
  # Account/schedule — delegated to Lending
  # ---------------------------------------------------------------------------

  defdelegate get_account!(id), to: Lending
  defdelegate list_accounts_for_customer(customer_id), to: Lending
  defdelegate close_account(account), to: Lending
  defdelegate write_off_account(account, admin_id), to: Lending
  defdelegate count_active_accounts(), to: Lending
  defdelegate total_outstanding_balance(), to: Lending
  defdelegate compound_interest_details(account), to: Lending
  defdelegate list_installments_for_account(loan_account_id), to: Lending
  defdelegate get_installment!(id), to: Lending
  defdelegate get_upcoming_installments(customer_id), to: Lending
  defdelegate mark_overdue_installments(), to: Lending
  defdelegate count_overdue_installments(customer_id \\ nil), to: Lending
  defdelegate total_overdue_amount(customer_id \\ nil), to: Lending
  defdelegate overdue_installments(), to: Lending
  defdelegate installments_due_soon(days \\ 7), to: Lending

  # ---------------------------------------------------------------------------
  # Payments
  # ---------------------------------------------------------------------------

  defdelegate list_transactions_for_account(loan_account_id), to: Payments
  defdelegate get_transaction!(id), to: Payments
  defdelegate record_payment(attrs \\ %{}), to: Payments
  defdelegate void_payment(transaction, attrs), to: Payments

  # ---------------------------------------------------------------------------
  # Ledger — delegated to Accounting
  # ---------------------------------------------------------------------------

  defdelegate list_entries_for_account(loan_account_id), to: Accounting
  defdelegate rebuild_outstanding_balance(loan_account_id), to: Accounting

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
