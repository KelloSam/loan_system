defmodule MiwayCreditCore.Repo.Migrations.CreateOrganisationSettings do
  use Ecto.Migration

  def change do
    create table(:organisation_settings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :organisation_id, references(:organisations, type: :binary_id), null: false
      add :currency, :string, default: "ZMW", null: false
      add :timezone, :string, default: "Africa/Lusaka", null: false

      timestamps()
    end

    create unique_index(:organisation_settings, [:organisation_id])
  end
end
