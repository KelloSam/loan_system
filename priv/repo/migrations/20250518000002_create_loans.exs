defmodule MiwayCreditCore.Repo.Migrations.CreateLoans do
  use Ecto.Migration

  def change do
    create table(:loans, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :amount, :decimal, precision: 15, scale: 2, null: false
      add :interest_rate, :decimal, precision: 6, scale: 2, null: false
      add :term_months, :integer, null: false
      add :status, :string, null: false, default: "pending"
      add :approved_at, :utc_datetime
      add :next_payment_date, :date
      add :remaining_balance, :decimal, precision: 15, scale: 2, null: false
      add :client_id, references(:clients, type: :binary_id, on_delete: :restrict), null: false

      timestamps()
    end

    create index(:loans, [:client_id])
    create index(:loans, [:status])
  end
end

