defmodule MiwayCreditCore.Loans.RepaymentScheduleInstallment do
  @moduledoc """
  One row of the repayment plan for a LoanAccount. Pure plan — never
  mutated directly by money-received logic. Only two things touch it:
  `MiwayCreditCore.Loans.Schedule.mark_overdue_installments/0` (flips
  status on time) and payment allocation (credits `paid_amount`).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(upcoming overdue paid partially_paid)

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "repayment_schedule_installments" do
    field :installment_number, :integer
    field :due_date, :date

    field :scheduled_amount, :decimal
    field :scheduled_principal, :decimal
    field :scheduled_interest, :decimal
    field :paid_amount, :decimal, default: Decimal.new("0.00")

    field :status, :string, default: "upcoming"
    field :paid_at, :utc_datetime

    belongs_to :loan_account, MiwayCreditCore.Loans.LoanAccount, type: :binary_id
    has_many :payment_allocations, MiwayCreditCore.Loans.PaymentAllocation

    timestamps()
  end

  def changeset(installment, attrs) do
    installment
    |> cast(attrs, [:loan_account_id, :installment_number, :due_date, :scheduled_amount,
                   :scheduled_principal, :scheduled_interest, :paid_amount, :status, :paid_at])
    |> validate_required([:loan_account_id, :installment_number, :due_date, :scheduled_amount,
                          :scheduled_principal, :scheduled_interest, :status])
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:scheduled_amount, greater_than: 0)
    |> validate_number(:paid_amount, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:loan_account_id)
  end
end
