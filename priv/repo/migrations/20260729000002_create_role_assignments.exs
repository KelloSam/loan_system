defmodule MiwayCreditCore.Repo.Migrations.CreateRoleAssignments do
  use Ecto.Migration

  def change do
    create table(:role_assignments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :organisation_membership_id, references(:organisation_memberships, type: :binary_id), null: false
      add :role_id, references(:roles, type: :binary_id), null: false
      add :branch_id, references(:branches, type: :binary_id)
      add :delegated_from_membership_id, references(:organisation_memberships, type: :binary_id)
      add :granted_by_id, references(:users)
      add :expires_at, :utc_datetime

      timestamps()
    end

    create index(:role_assignments, [:organisation_membership_id])
    create index(:role_assignments, [:role_id])
  end
end
