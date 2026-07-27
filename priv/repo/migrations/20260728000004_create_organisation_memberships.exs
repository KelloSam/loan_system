defmodule MiwayCreditCore.Repo.Migrations.CreateOrganisationMemberships do
  use Ecto.Migration

  def change do
    create table(:organisation_memberships, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :staff_member_id, references(:staff_members, type: :binary_id), null: false
      add :organisation_id, references(:organisations, type: :binary_id), null: false
      add :status, :string, default: "active", null: false

      timestamps()
    end

    create unique_index(:organisation_memberships, [:staff_member_id, :organisation_id])
    create index(:organisation_memberships, [:organisation_id])
  end
end
