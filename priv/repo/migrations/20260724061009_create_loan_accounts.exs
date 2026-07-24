defmodule MiwayCreditCore.Repo.Migrations.CreateLoanAccounts do
  use Ecto.Migration

  def change do
    create table(:loan_accounts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :loan_application_id, references(:loan_applications, type: :binary_id), null: false
      add :client_id, references(:clients, type: :binary_id), null: false

      add :principal_amount, :decimal, precision: 15, scale: 2, null: false
      add :interest_rate, :decimal, precision: 6, scale: 2, null: false
      add :term_months, :integer, null: false

      add :opened_at, :utc_datetime, null: false
      add :status, :string, default: "active", null: false
      add :outstanding_balance, :decimal, precision: 15, scale: 2, null: false
      add :closed_at, :utc_datetime

      timestamps()
    end

    create unique_index(:loan_accounts, [:loan_application_id])
    create index(:loan_accounts, [:client_id])
    create index(:loan_accounts, [:status])
  end
end
