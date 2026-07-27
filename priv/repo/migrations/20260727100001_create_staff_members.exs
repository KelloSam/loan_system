defmodule MiwayCreditCore.Repo.Migrations.CreateStaffMembers do
  use Ecto.Migration

  def change do
    create table(:staff_members, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users), null: false
      add :role, :string, null: false

      timestamps()
    end

    create unique_index(:staff_members, [:user_id])
  end
end
