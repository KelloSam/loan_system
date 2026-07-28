defmodule MiwayCreditCore.Repo.Migrations.CreateRoles do
  use Ecto.Migration

  def change do
    create table(:roles, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :organisation_id, references(:organisations, type: :binary_id), null: false
      add :name, :string, null: false
      add :description, :string

      timestamps()
    end

    create unique_index(:roles, [:organisation_id, :name])
  end
end
