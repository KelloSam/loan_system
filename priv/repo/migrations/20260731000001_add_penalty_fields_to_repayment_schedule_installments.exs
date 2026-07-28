defmodule MiwayCreditCore.Repo.Migrations.AddPenaltyFieldsToRepaymentScheduleInstallments do
  @moduledoc """
  Step 13: penalty_amount (accrued when an installment goes overdue,
  see Lending.Schedule.mark_overdue_installments/0) and penalty_paid
  (credited by payment allocation). Constant zero default applies
  correctly to every existing row — no installment has accrued a
  penalty before this migration exists.
  """

  use Ecto.Migration

  def change do
    alter table(:repayment_schedule_installments) do
      add :penalty_amount, :decimal, null: false, default: 0.0
      add :penalty_paid, :decimal, null: false, default: 0.0
    end
  end
end
