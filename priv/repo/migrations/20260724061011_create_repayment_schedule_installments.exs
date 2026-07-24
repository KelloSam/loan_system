defmodule MiwayCreditCore.Repo.Migrations.CreateRepaymentScheduleInstallments do
  use Ecto.Migration

  def change do
    create table(:repayment_schedule_installments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :loan_account_id, references(:loan_accounts, type: :binary_id), null: false

      add :installment_number, :integer, null: false
      add :due_date, :date, null: false

      add :scheduled_amount, :decimal, precision: 15, scale: 2, null: false
      add :scheduled_principal, :decimal, precision: 15, scale: 2, null: false
      add :scheduled_interest, :decimal, precision: 15, scale: 2, null: false
      add :paid_amount, :decimal, precision: 15, scale: 2, default: 0, null: false

      add :status, :string, default: "upcoming", null: false
      add :paid_at, :utc_datetime

      timestamps()
    end

    create index(:repayment_schedule_installments, [:loan_account_id, :due_date])
    create index(:repayment_schedule_installments, [:status])
  end
end
