defmodule MiwayCreditCore.Lending.LoanAccount do
  @moduledoc """
  The credit actually extended. Created exactly once, when a
  LoanApplication is approved — never re-created for the same
  application (enforced by a unique index on loan_application_id).

  `outstanding_balance` is a materialized cache: the ledger
  (AccountingEntry) is the source of truth, and this field is only ever
  written inside the same Ecto.Multi that inserts the corresponding
  ledger entry, so it cannot drift under normal operation. See
  `MiwayCreditCore.Accounting.rebuild_outstanding_balance/1`.

  `loan_product_id` is traceability only, for reporting — the actual
  terms (`interest_rate`, `interest_method`, `term_months`) are frozen
  onto this record directly at approval time and never re-read from
  the product afterward, so editing or retiring a `LoanProduct` later
  never changes an existing account's terms.

  `contract_reference` is system-generated at disbursement time (see
  `generate_contract_reference/1`), never user-entered.
  `disbursement_method`/`disbursement_reference` are the outbound
  mirror of `MiwayCreditCore.Payments.PaymentTransaction`'s existing
  `method`/`reference` fields — same channel vocabulary, opposite
  direction of money movement.

  A `"reversed"` account is a disbursement that was wrong from the
  start (see `MiwayCreditCore.Lending.Servicing.reverse_disbursement/3`)
  — distinct from `"written_off"` (a real loan that went bad) or
  `"closed"` (a real loan paid off): the loan itself should never have
  existed, not that it failed.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(active closed written_off defaulted reversed)
  @disbursement_methods ~w(cash bank_transfer mobile_money cheque other)

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "loan_accounts" do
    field :principal_amount, :decimal
    field :interest_rate, :decimal
    field :interest_method, :string
    field :term_months, :integer

    field :contract_reference, :string
    field :disbursement_method, :string
    field :disbursement_reference, :string

    field :opened_at, :utc_datetime
    field :status, :string, default: "active"
    field :outstanding_balance, :decimal
    field :closed_at, :utc_datetime

    field :reversed_at, :utc_datetime
    field :reversal_reason, :string

    belongs_to :organisation, MiwayCreditCore.Organisations.Organisation, type: :binary_id
    belongs_to :loan_application, MiwayCreditCore.Applications.LoanApplication, type: :binary_id
    belongs_to :customer, MiwayCreditCore.Customers.Customer, type: :binary_id
    belongs_to :loan_product, MiwayCreditCore.Products.LoanProduct, type: :binary_id
    belongs_to :reversed_by, MiwayCreditCore.Accounts.User

    has_many :repayment_schedule_installments,
             MiwayCreditCore.Lending.RepaymentScheduleInstallment,
             preload_order: [asc: :due_date]

    has_many :payment_transactions, MiwayCreditCore.Payments.PaymentTransaction
    has_many :accounting_entries, MiwayCreditCore.Accounting.AccountingEntry
    has_many :collaterals, MiwayCreditCore.Applications.Collateral

    timestamps()
  end

  @doc """
  `"LN-<year>-<8 uppercase hex chars>"`, derived from the account's own
  id — the id is generated client-side before insert (same technique
  `MiwayCreditCore.Applications.generate_repayment_schedule/3` already
  uses for installment ids), so this can be computed and inserted in
  the same write, no separate lookup step needed.
  """
  def generate_contract_reference(id) do
    year = Date.utc_today().year
    suffix = id |> String.replace("-", "") |> String.slice(0, 8) |> String.upcase()
    "LN-#{year}-#{suffix}"
  end

  def changeset(loan_account, attrs) do
    loan_account
    |> cast(attrs, [
      :organisation_id,
      :loan_application_id,
      :customer_id,
      :loan_product_id,
      :principal_amount,
      :interest_rate,
      :interest_method,
      :term_months,
      :contract_reference,
      :disbursement_method,
      :disbursement_reference,
      :opened_at,
      :status,
      :outstanding_balance,
      :closed_at,
      :reversed_at,
      :reversed_by_id,
      :reversal_reason
    ])
    |> validate_required([
      :organisation_id,
      :loan_application_id,
      :customer_id,
      :loan_product_id,
      :principal_amount,
      :interest_rate,
      :interest_method,
      :term_months,
      :contract_reference,
      :disbursement_method,
      :opened_at,
      :status,
      :outstanding_balance
    ])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:disbursement_method, @disbursement_methods)
    |> validate_number(:principal_amount, greater_than: 0)
    |> validate_number(:interest_rate, greater_than: 0)
    |> validate_number(:term_months, greater_than: 0)
    |> validate_number(:outstanding_balance, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:organisation_id)
    |> foreign_key_constraint(:loan_application_id)
    |> foreign_key_constraint(:customer_id)
    |> foreign_key_constraint(:loan_product_id)
    |> foreign_key_constraint(:reversed_by_id)
    |> unique_constraint(:loan_application_id)
    |> unique_constraint(:contract_reference)
  end
end
