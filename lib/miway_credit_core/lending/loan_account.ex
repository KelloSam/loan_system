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
  """

  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(active closed written_off defaulted)

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "loan_accounts" do
    field :principal_amount, :decimal
    field :interest_rate, :decimal
    field :term_months, :integer

    field :opened_at, :utc_datetime
    field :status, :string, default: "active"
    field :outstanding_balance, :decimal
    field :closed_at, :utc_datetime

    belongs_to :loan_application, MiwayCreditCore.Loans.LoanApplication, type: :binary_id
    belongs_to :customer, MiwayCreditCore.Customers.Customer, type: :binary_id

    has_many :repayment_schedule_installments, MiwayCreditCore.Lending.RepaymentScheduleInstallment,
      preload_order: [asc: :due_date]
    has_many :payment_transactions, MiwayCreditCore.Payments.PaymentTransaction
    has_many :accounting_entries, MiwayCreditCore.Accounting.AccountingEntry
    has_many :collaterals, MiwayCreditCore.Loans.Collateral

    timestamps()
  end

  def changeset(loan_account, attrs) do
    loan_account
    |> cast(attrs, [:loan_application_id, :customer_id, :principal_amount, :interest_rate,
                   :term_months, :opened_at, :status, :outstanding_balance, :closed_at])
    |> validate_required([:loan_application_id, :customer_id, :principal_amount, :interest_rate,
                          :term_months, :opened_at, :status, :outstanding_balance])
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:principal_amount, greater_than: 0)
    |> validate_number(:interest_rate, greater_than: 0)
    |> validate_number(:term_months, greater_than: 0)
    |> validate_number(:outstanding_balance, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:loan_application_id)
    |> foreign_key_constraint(:customer_id)
    |> unique_constraint(:loan_application_id)
  end
end
