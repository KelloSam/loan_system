defmodule MiwayCreditCore.Repo.Migrations.CreateConsents do
  use Ecto.Migration

  def change do
    create table(:consents, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :organisation_id, references(:organisations, type: :binary_id), null: false
      add :customer_id, references(:customers, type: :binary_id), null: false

      add :consent_type, :string, null: false
      add :method, :string, null: false
      add :granted_at, :utc_datetime, null: false
      add :revoked_at, :utc_datetime
      add :recorded_by_id, references(:users), null: false

      timestamps()
    end

    create index(:consents, [:organisation_id, :customer_id])
  end
end
