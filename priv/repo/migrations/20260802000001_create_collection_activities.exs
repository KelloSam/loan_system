defmodule MiwayCreditCore.Repo.Migrations.CreateCollectionActivities do
  @moduledoc """
  Step 15: the chronological communication-history log for a
  collection case, and — filtered by a future follow_up_date — the
  pending follow-up queue. One entity for both, not two. Insert-only,
  same posture as AccountingEntry/ApprovalDecision.
  """

  use Ecto.Migration

  def change do
    create table(:collection_activities, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :organisation_id, references(:organisations, type: :binary_id), null: false
      add :collection_case_id, references(:collection_cases, type: :binary_id), null: false
      add :activity_type, :string, null: false
      add :outcome, :string, null: false
      add :notes, :string
      add :occurred_at, :utc_datetime, null: false
      add :follow_up_date, :date
      add :recorded_by_id, references(:users), null: false

      timestamps(updated_at: false)
    end

    create index(:collection_activities, [:collection_case_id])
    create index(:collection_activities, [:follow_up_date])
  end
end
