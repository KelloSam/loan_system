defmodule MiwayCreditCore.Loans do
  @moduledoc """
  Deprecated compatibility facade over the old loan-origination domain.
  Every function here delegates to a top-level context — call that
  context directly in new code, this module owns no logic of its own
  anymore.

  | Old call | New home |
  |---|---|
  | application/collateral functions | `MiwayCreditCore.Applications` |
  | account/schedule/installment functions | `MiwayCreditCore.Lending` |
  | payment/transaction functions | `MiwayCreditCore.Payments` |
  | ledger/balance functions | `MiwayCreditCore.Accounting` |

  See `docs/architecture/context_boundaries.md`. Removal target: once
  `lib/miway_credit_core_web/controllers/loan_controller.ex` calls the
  four contexts above directly, delete this module.
  """

  alias MiwayCreditCore.{Applications, Lending, Accounting, Payments}

  # ---------------------------------------------------------------------------
  # Applications — delegated to Applications
  # ---------------------------------------------------------------------------

  @deprecated "Use MiwayCreditCore.Applications.list_applications/1"
  defdelegate list_applications(opts \\ []), to: Applications

  @deprecated "Use MiwayCreditCore.Applications.get_applications_for_customer/1"
  defdelegate get_applications_for_customer(customer_id), to: Applications

  @deprecated "Use MiwayCreditCore.Applications.get_application!/1"
  defdelegate get_application!(id), to: Applications

  @deprecated "Use MiwayCreditCore.Applications.create_application/1"
  defdelegate create_application(attrs \\ %{}), to: Applications

  @deprecated "Use MiwayCreditCore.Applications.update_application/2"
  defdelegate update_application(application, attrs), to: Applications

  @deprecated "Use MiwayCreditCore.Applications.delete_application/1"
  defdelegate delete_application(application), to: Applications

  @deprecated "Use MiwayCreditCore.Applications.approve_application/2"
  defdelegate approve_application(application, admin_id), to: Applications

  @deprecated "Use MiwayCreditCore.Applications.reject_application/3"
  defdelegate reject_application(application, admin_id, reason), to: Applications

  @deprecated "Use MiwayCreditCore.Applications.fraud_signals/1"
  defdelegate fraud_signals(application), to: Applications

  @deprecated "Use MiwayCreditCore.Applications.count_applications/0"
  defdelegate count_applications(), to: Applications

  @deprecated "Use MiwayCreditCore.Applications.count_active_applications/0"
  defdelegate count_active_applications(), to: Applications

  # ---------------------------------------------------------------------------
  # Account/schedule — delegated to Lending
  # ---------------------------------------------------------------------------

  @deprecated "Use MiwayCreditCore.Lending.get_account!/1"
  defdelegate get_account!(id), to: Lending

  @deprecated "Use MiwayCreditCore.Lending.list_accounts_for_customer/1"
  defdelegate list_accounts_for_customer(customer_id), to: Lending

  @deprecated "Use MiwayCreditCore.Lending.close_account/1"
  defdelegate close_account(account), to: Lending

  @deprecated "Use MiwayCreditCore.Lending.write_off_account/2"
  defdelegate write_off_account(account, admin_id), to: Lending

  @deprecated "Use MiwayCreditCore.Lending.count_active_accounts/0"
  defdelegate count_active_accounts(), to: Lending

  @deprecated "Use MiwayCreditCore.Lending.total_outstanding_balance/0"
  defdelegate total_outstanding_balance(), to: Lending

  @deprecated "Use MiwayCreditCore.Lending.compound_interest_details/1"
  defdelegate compound_interest_details(account), to: Lending

  @deprecated "Use MiwayCreditCore.Lending.list_installments_for_account/1"
  defdelegate list_installments_for_account(loan_account_id), to: Lending

  @deprecated "Use MiwayCreditCore.Lending.get_installment!/1"
  defdelegate get_installment!(id), to: Lending

  @deprecated "Use MiwayCreditCore.Lending.get_upcoming_installments/1"
  defdelegate get_upcoming_installments(customer_id), to: Lending

  @deprecated "Use MiwayCreditCore.Lending.mark_overdue_installments/0"
  defdelegate mark_overdue_installments(), to: Lending

  @deprecated "Use MiwayCreditCore.Lending.count_overdue_installments/1"
  defdelegate count_overdue_installments(customer_id \\ nil), to: Lending

  @deprecated "Use MiwayCreditCore.Lending.total_overdue_amount/1"
  defdelegate total_overdue_amount(customer_id \\ nil), to: Lending

  @deprecated "Use MiwayCreditCore.Lending.overdue_installments/0"
  defdelegate overdue_installments(), to: Lending

  @deprecated "Use MiwayCreditCore.Lending.installments_due_soon/1"
  defdelegate installments_due_soon(days \\ 7), to: Lending

  # ---------------------------------------------------------------------------
  # Payments — delegated to the top-level Payments context
  # ---------------------------------------------------------------------------

  @deprecated "Use MiwayCreditCore.Payments.list_transactions_for_account/1"
  defdelegate list_transactions_for_account(loan_account_id), to: Payments

  @deprecated "Use MiwayCreditCore.Payments.get_transaction!/1"
  defdelegate get_transaction!(id), to: Payments

  @deprecated "Use MiwayCreditCore.Payments.record_payment/1"
  defdelegate record_payment(attrs \\ %{}), to: Payments

  @deprecated "Use MiwayCreditCore.Payments.void_payment/2"
  defdelegate void_payment(transaction, attrs), to: Payments

  # ---------------------------------------------------------------------------
  # Ledger — delegated to Accounting
  # ---------------------------------------------------------------------------

  @deprecated "Use MiwayCreditCore.Accounting.list_entries_for_account/1"
  defdelegate list_entries_for_account(loan_account_id), to: Accounting

  @deprecated "Use MiwayCreditCore.Accounting.rebuild_outstanding_balance/1"
  defdelegate rebuild_outstanding_balance(loan_account_id), to: Accounting

  # ---------------------------------------------------------------------------
  # Collateral — delegated to Applications
  # ---------------------------------------------------------------------------

  @deprecated "Use MiwayCreditCore.Applications.list_collaterals_for_account/1"
  defdelegate list_collaterals_for_account(loan_account_id), to: Applications

  @deprecated "Use MiwayCreditCore.Applications.get_collateral!/1"
  defdelegate get_collateral!(id), to: Applications

  @deprecated "Use MiwayCreditCore.Applications.create_collateral/1"
  defdelegate create_collateral(attrs \\ %{}), to: Applications

  @deprecated "Use MiwayCreditCore.Applications.delete_collateral/1"
  defdelegate delete_collateral(collateral), to: Applications

  @deprecated "Use MiwayCreditCore.Applications.total_collateral_value/1"
  defdelegate total_collateral_value(loan_account_id), to: Applications
end
