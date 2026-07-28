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

  @components ~w(penalty interest principal)

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "payment_allocations" do
    field :allocated_amount, :decimal
    field :component, :string

    belongs_to :organisation, MiwayCreditCore.Organisations.Organisation, type: :binary_id
    belongs_to :payment_transaction, MiwayCreditCore.Payments.PaymentTransaction, type: :binary_id
    belongs_to :repayment_schedule_installment, MiwayCreditCore.Lending.RepaymentScheduleInstallment,
      type: :binary_id

    timestamps(updated_at: false)
  end

  def changeset(allocation, attrs) do
    allocation
    |> cast(attrs, [:organisation_id, :payment_transaction_id, :repayment_schedule_installment_id,
                   :allocated_amount, :component])
    |> validate_required([:organisation_id, :payment_transaction_id, :repayment_schedule_installment_id,
                          :allocated_amount, :component])
    |> validate_number(:allocated_amount, greater_than: 0)
    |> validate_inclusion(:component, @components)
    |> foreign_key_constraint(:organisation_id)
    |> foreign_key_constraint(:payment_transaction_id)
    |> foreign_key_constraint(:repayment_schedule_installment_id)
  end
end
