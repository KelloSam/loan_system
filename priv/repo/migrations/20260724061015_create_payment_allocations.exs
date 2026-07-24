defmodule MiwayCreditCore.Repo.Migrations.CreatePaymentAllocations do
  use Ecto.Migration

  def change do
    create table(:payment_allocations, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :payment_transaction_id, references(:payment_transactions, type: :binary_id),
        null: false

      add :repayment_schedule_installment_id,
        references(:repayment_schedule_installments, type: :binary_id), null: false

      add :allocated_amount, :decimal, precision: 15, scale: 2, null: false

      timestamps(updated_at: false)
    end

    create index(:payment_allocations, [:payment_transaction_id])
    create index(:payment_allocations, [:repayment_schedule_installment_id])
  end
end
