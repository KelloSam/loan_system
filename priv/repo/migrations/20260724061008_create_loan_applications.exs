defmodule MiwayCreditCore.Repo.Migrations.CreateLoanApplications do
  use Ecto.Migration

  def change do
    create table(:loan_applications, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :client_id, references(:clients, type: :binary_id), null: false

      add :requested_amount, :decimal, precision: 15, scale: 2, null: false
      add :requested_term_months, :integer, null: false
      add :purpose, :string

      add :risk_level, :string, default: "low", null: false
      add :risk_score, :integer

      add :status, :string, default: "pending", null: false
      add :decided_at, :utc_datetime
      add :decided_by_id, references(:users)
      add :rejection_reason, :string

      timestamps()
    end

    create index(:loan_applications, [:client_id])
    create index(:loan_applications, [:status])
    create index(:loan_applications, [:decided_by_id])
  end
end
