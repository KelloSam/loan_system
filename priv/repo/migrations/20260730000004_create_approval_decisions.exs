defmodule MiwayCreditCore.Repo.Migrations.CreateApprovalDecisions do
  @moduledoc """
  The per-level decision trail a multi-level or committee approval
  needs — a single LoanApplication.decided_by_id/decided_at can only
  capture one decision, but a two-level or committee-of-N product
  produces several. Never edited or deleted, same append-only posture
  as accounting_entries/audit_logs.
  """

  use Ecto.Migration

  def change do
    create table(:approval_decisions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :organisation_id, references(:organisations, type: :binary_id), null: false
      add :loan_application_id, references(:loan_applications, type: :binary_id), null: false

      add :level, :integer, null: false
      add :decision, :string, null: false
      add :notes, :text
      add :decline_reason_category, :string
      add :conditions, :text

      add :decided_by_id, references(:users), null: false
      add :decided_at, :utc_datetime, null: false

      timestamps(updated_at: false)
    end

    create index(:approval_decisions, [:organisation_id, :loan_application_id])
  end
end
