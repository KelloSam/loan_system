defmodule MiwayCreditCore.Repo.Migrations.CreateRolePermissions do
  use Ecto.Migration

  def change do
    create table(:role_permissions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :role_id, references(:roles, type: :binary_id), null: false
      add :permission_key, :string, null: false

      timestamps(updated_at: false)
    end

    create unique_index(:role_permissions, [:role_id, :permission_key])
  end
end
