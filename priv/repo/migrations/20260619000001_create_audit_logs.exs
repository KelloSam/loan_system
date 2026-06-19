defmodule LoanSystem.Repo.Migrations.CreateAuditLogs do
  use Ecto.Migration

  def change do
    create table(:audit_logs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :event, :string, null: false
      add :actor_id, :binary_id
      add :actor_email, :string
      add :target_type, :string
      add :target_id, :string
      add :metadata, :map, default: %{}
      add :ip_address, :string

      timestamps(updated_at: false)
    end

    create index(:audit_logs, [:inserted_at])
    create index(:audit_logs, [:actor_id])
    create index(:audit_logs, [:event])
  end
end
