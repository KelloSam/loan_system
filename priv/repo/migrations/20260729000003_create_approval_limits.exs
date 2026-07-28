defmodule MiwayCreditCore.Repo.Migrations.CreateApprovalLimits do
  use Ecto.Migration

  def change do
    create table(:approval_limits, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :role_id, references(:roles, type: :binary_id), null: false
      add :permission_key, :string, null: false
      add :max_amount, :decimal, precision: 15, scale: 2, null: false

      timestamps()
    end

    create unique_index(:approval_limits, [:role_id, :permission_key])
  end
end
