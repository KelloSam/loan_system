defmodule MiwayCreditCore.Repo.Migrations.CreateStaffBranchAssignments do
  use Ecto.Migration

  def change do
    create table(:staff_branch_assignments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :organisation_membership_id, references(:organisation_memberships, type: :binary_id), null: false
      add :branch_id, references(:branches, type: :binary_id), null: false

      timestamps()
    end

    create unique_index(:staff_branch_assignments, [:organisation_membership_id, :branch_id])
    create index(:staff_branch_assignments, [:branch_id])
  end
end
