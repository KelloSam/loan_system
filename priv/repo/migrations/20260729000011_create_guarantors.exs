defmodule MiwayCreditCore.Repo.Migrations.CreateGuarantors do
  use Ecto.Migration

  def change do
    create table(:guarantors, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :organisation_id, references(:organisations, type: :binary_id), null: false
      add :customer_id, references(:customers, type: :binary_id), null: false

      add :name, :string, null: false
      add :relationship, :string, null: false
      add :phone, :string, null: false
      add :id_type, :string, null: false
      add :id_number, :string, null: false
      add :address_line, :string

      timestamps()
    end

    create index(:guarantors, [:organisation_id, :customer_id])
  end
end
