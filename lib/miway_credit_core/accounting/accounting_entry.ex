defmodule MiwayCreditCore.Accounting.AccountingEntry do
  @moduledoc """
  Immutable, insert-only ledger row — the single source of truth for a
  LoanAccount's balance history. A per-account subledger (signed amount
  + running balance), not a full double-entry general ledger: this app
  tracks one account's balance over time, not a multi-account chart of
  accounts. `entry_type` leaves the door open to translate into a real
  GL later if ever needed.

  No update changeset is exposed anywhere in this module or the
  `MiwayCreditCore.Accounting.Ledger` context — immutability is enforced at
  the context layer, the same pattern `AuditLogs` uses.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @entry_types ~w(disbursement repayment fee write_off reversal)
  @source_types ~w(payment_transaction loan_account manual_adjustment)

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "accounting_entries" do
    field :entry_type, :string
    field :amount, :decimal
    field :running_balance, :decimal

    field :source_type, :string
    field :source_id, :binary_id
    field :description, :string

    field :occurred_at, :utc_datetime

    belongs_to :loan_account, MiwayCreditCore.Lending.LoanAccount, type: :binary_id
    belongs_to :recorded_by, MiwayCreditCore.Accounts.User

    timestamps(updated_at: false)
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:loan_account_id, :entry_type, :amount, :running_balance, :source_type,
                   :source_id, :description, :recorded_by_id, :occurred_at])
    |> validate_required([:loan_account_id, :entry_type, :amount, :running_balance, :source_type,
                          :occurred_at])
    |> validate_inclusion(:entry_type, @entry_types)
    |> validate_inclusion(:source_type, @source_types)
    |> foreign_key_constraint(:loan_account_id)
    |> foreign_key_constraint(:recorded_by_id)
  end
end
