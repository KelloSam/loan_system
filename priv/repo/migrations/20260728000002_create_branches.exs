defmodule MiwayCreditCore.Repo.Migrations.CreateBranches do
  use Ecto.Migration

  def change do
    create table(:branches, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :organisation_id, references(:organisations, type: :binary_id), null: false
      add :name, :string, null: false
      add :code, :string, null: false
      add :address, :string
      add :active, :boolean, default: true, null: false

      timestamps()
    end

    create unique_index(:branches, [:organisation_id, :code])
    create index(:branches, [:organisation_id])
  end
end
