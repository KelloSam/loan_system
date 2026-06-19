defmodule LoanSystem.Repo.Migrations.AddRiskLevelToLoans do
  use Ecto.Migration

  def change do
    alter table(:loans) do
      add :risk_level, :string, default: "low"
    end

    create index(:loans, [:risk_level])
  end
end
