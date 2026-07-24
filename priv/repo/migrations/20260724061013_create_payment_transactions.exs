defmodule MiwayCreditCore.Repo.Migrations.CreatePaymentTransactions do
  use Ecto.Migration

  def change do
    create table(:payment_transactions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :loan_account_id, references(:loan_accounts, type: :binary_id), null: false

      add :amount, :decimal, precision: 15, scale: 2, null: false
      add :received_at, :utc_datetime, null: false
      add :method, :string, null: false
      add :reference, :string
      add :recorded_by_id, references(:users), null: false
      add :notes, :string

      add :status, :string, default: "posted", null: false
      add :voided_at, :utc_datetime
      add :voided_by_id, references(:users)
      add :void_reason, :string

      timestamps()
    end

    create index(:payment_transactions, [:loan_account_id])
    create index(:payment_transactions, [:recorded_by_id])
    create index(:payment_transactions, [:status])
  end
end
