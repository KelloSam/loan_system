defmodule MiwayCreditCore.Repo.Migrations.CreateDepartments do
  use Ecto.Migration

  def change do
    create table(:departments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :organisation_id, references(:organisations, type: :binary_id), null: false
      add :name, :string, null: false

      timestamps()
    end

    create unique_index(:departments, [:organisation_id, :name])
  end
end
