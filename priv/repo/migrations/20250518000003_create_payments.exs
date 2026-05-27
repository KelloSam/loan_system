defmodule LoanSystem.Repo.Migrations.CreatePayments do
  use Ecto.Migration

  def change do
    create table(:payments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :amount, :decimal, precision: 15, scale: 2, null: false
      add :payment_date, :utc_datetime, null: false
      add :status, :string, null: false, default: "pending"
      add :loan_id, references(:loans, type: :binary_id, on_delete: :restrict), null: false

      timestamps()
    end

    create index(:payments, [:loan_id])
    create index(:payments, [:payment_date])
    create index(:payments, [:status])
  end
end

