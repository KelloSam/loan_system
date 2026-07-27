defmodule MiwayCreditCore.Payments.PaymentTransaction do
  @moduledoc """
  Money actually received from a customer. Never hard-deleted — a
  mis-recorded payment is voided (see `MiwayCreditCore.Payments.void_payment/2`),
  which flips `status` to "voided" and reverses its effect via a
  compensating AccountingEntry, preserving the audit trail.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @methods ~w(cash bank_transfer mobile_money cheque other)
  @statuses ~w(posted voided)

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "payment_transactions" do
    field :amount, :decimal
    field :received_at, :utc_datetime
    field :method, :string
    field :reference, :string
    field :notes, :string

    field :status, :string, default: "posted"
    field :voided_at, :utc_datetime
    field :void_reason, :string

    belongs_to :loan_account, MiwayCreditCore.Lending.LoanAccount, type: :binary_id
    belongs_to :recorded_by, MiwayCreditCore.Accounts.User
    belongs_to :voided_by, MiwayCreditCore.Accounts.User

    has_many :payment_allocations, MiwayCreditCore.Payments.PaymentAllocation

    timestamps()
  end

  def changeset(payment_transaction, attrs) do
    payment_transaction
    |> cast(attrs, [:loan_account_id, :amount, :received_at, :method, :reference,
                   :recorded_by_id, :notes])
    |> validate_required([:loan_account_id, :amount, :received_at, :method, :recorded_by_id])
    |> validate_inclusion(:method, @methods)
    |> validate_number(:amount, greater_than: 0)
    |> foreign_key_constraint(:loan_account_id)
    |> foreign_key_constraint(:recorded_by_id)
  end

  def void_changeset(payment_transaction, attrs) do
    payment_transaction
    |> cast(attrs, [:status, :voided_at, :voided_by_id, :void_reason])
    |> validate_required([:status, :voided_at, :voided_by_id, :void_reason])
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:voided_by_id)
  end
end
