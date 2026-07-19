defmodule LoanSystem.Repo.Migrations.CreateCollaterals do
  use Ecto.Migration

  def change do
    create table(:collaterals, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :type, :string, null: false
      add :description, :string, null: false
      add :estimated_value, :decimal, precision: 15, scale: 2, null: false
      add :loan_id, references(:loans, type: :binary_id, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:collaterals, [:loan_id])
  end
end
