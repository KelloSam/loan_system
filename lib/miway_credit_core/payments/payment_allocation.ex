defmodule MiwayCreditCore.Payments.PaymentAllocation do
  @moduledoc """
  Links a PaymentTransaction to the installment(s) it satisfies. A join
  table rather than a direct FK on the transaction because a single
  transaction can satisfy more than one installment (catch-up payment)
  and a single installment can be satisfied across more than one
  transaction (partial payments) — both ordinary in loan servicing.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "payment_allocations" do
    field :allocated_amount, :decimal

    belongs_to :payment_transaction, MiwayCreditCore.Payments.PaymentTransaction, type: :binary_id
    belongs_to :repayment_schedule_installment, MiwayCreditCore.Lending.RepaymentScheduleInstallment,
      type: :binary_id

    timestamps(updated_at: false)
  end

  def changeset(allocation, attrs) do
    allocation
    |> cast(attrs, [:payment_transaction_id, :repayment_schedule_installment_id, :allocated_amount])
    |> validate_required([:payment_transaction_id, :repayment_schedule_installment_id,
                          :allocated_amount])
    |> validate_number(:allocated_amount, greater_than: 0)
    |> foreign_key_constraint(:payment_transaction_id)
    |> foreign_key_constraint(:repayment_schedule_installment_id)
  end
end
