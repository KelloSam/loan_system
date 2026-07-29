defmodule MiwayCreditCore.Payments.PaymentTransaction do
  @moduledoc """
  Money actually received from a customer. Never hard-deleted — a
  mis-recorded payment is voided (see `MiwayCreditCore.Payments.void_payment/2`),
  which flips `status` to "voided" and reverses its effect via a
  compensating AccountingEntry, preserving the audit trail.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @methods ~w(cash bank_transfer mobile_money cheque payroll_deduction other)
  @statuses ~w(posted voided failed)

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "payment_transactions" do
    field :amount, :decimal
    field :payable_amount, :decimal
    field :overpayment_amount, :decimal, default: Decimal.new("0.00")
    field :received_at, :utc_datetime
    field :method, :string
    field :reference, :string
    field :notes, :string

    field :status, :string, default: "posted"
    field :voided_at, :utc_datetime
    field :void_reason, :string

    # A client-supplied nonce, one per form render — lets record_payment/2
    # tell a genuine second payment apart from a double-submit of the
    # same one. Optional: only form-originated payments carry it.
    field :idempotency_key, :string

    field :failed_at, :utc_datetime
    field :fail_reason, :string

    belongs_to :organisation, MiwayCreditCore.Organisations.Organisation, type: :binary_id
    belongs_to :loan_account, MiwayCreditCore.Lending.LoanAccount, type: :binary_id
    belongs_to :recorded_by, MiwayCreditCore.Accounts.User
    belongs_to :voided_by, MiwayCreditCore.Accounts.User
    belongs_to :failed_by, MiwayCreditCore.Accounts.User

    has_many :payment_allocations, MiwayCreditCore.Payments.PaymentAllocation

    timestamps()
  end

  def changeset(payment_transaction, attrs) do
    payment_transaction
    |> cast(attrs, [:organisation_id, :loan_account_id, :amount, :payable_amount, :overpayment_amount,
                   :received_at, :method, :reference, :recorded_by_id, :notes, :idempotency_key])
    |> validate_required([:organisation_id, :loan_account_id, :amount, :payable_amount, :received_at, :method,
                          :recorded_by_id])
    |> validate_inclusion(:method, @methods)
    |> validate_number(:amount, greater_than: 0)
    |> validate_number(:payable_amount, greater_than_or_equal_to: 0)
    |> validate_number(:overpayment_amount, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:organisation_id)
    |> foreign_key_constraint(:loan_account_id)
    |> foreign_key_constraint(:recorded_by_id)
    |> unique_constraint(:idempotency_key, name: :payment_transactions_loan_account_id_idempotency_key_index)
  end

  @doc "Records a payment attempt that never reconciled — no allocation or balance effect."
  def failed_attempt_changeset(payment_transaction, attrs) do
    payment_transaction
    |> cast(attrs, [:organisation_id, :loan_account_id, :amount, :received_at, :method, :reference,
                   :recorded_by_id, :notes, :fail_reason])
    |> put_change(:status, "failed")
    |> put_change(:payable_amount, Decimal.new("0.00"))
    |> validate_required([:organisation_id, :loan_account_id, :amount, :received_at, :method, :recorded_by_id,
                          :fail_reason])
    |> validate_inclusion(:method, @methods)
    |> validate_number(:amount, greater_than: 0)
    |> foreign_key_constraint(:organisation_id)
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

  @doc "Marks a previously-posted payment as failed after the fact (e.g. a bounced cheque)."
  def fail_changeset(payment_transaction, attrs) do
    payment_transaction
    |> cast(attrs, [:status, :failed_at, :failed_by_id, :fail_reason])
    |> validate_required([:status, :failed_at, :failed_by_id, :fail_reason])
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:failed_by_id)
  end
end
