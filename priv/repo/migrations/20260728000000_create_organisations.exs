defmodule MiwayCreditCore.Repo.Migrations.CreateOrganisations do
  use Ecto.Migration

  def change do
    create table(:organisations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :status, :string, default: "active", null: false

      timestamps()
    end

    create unique_index(:organisations, [:name])
  end
end
