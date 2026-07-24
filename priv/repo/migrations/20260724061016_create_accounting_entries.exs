defmodule MiwayCreditCore.Repo.Migrations.CreateAccountingEntries do
  use Ecto.Migration

  def change do
    create table(:accounting_entries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :loan_account_id, references(:loan_accounts, type: :binary_id), null: false

      add :entry_type, :string, null: false
      add :amount, :decimal, precision: 15, scale: 2, null: false
      add :running_balance, :decimal, precision: 15, scale: 2, null: false

      add :source_type, :string, null: false
      add :source_id, :binary_id
      add :description, :string
      add :recorded_by_id, references(:users)

      add :occurred_at, :utc_datetime, null: false

      timestamps(updated_at: false)
    end

    create index(:accounting_entries, [:loan_account_id, :inserted_at])
  end
end
