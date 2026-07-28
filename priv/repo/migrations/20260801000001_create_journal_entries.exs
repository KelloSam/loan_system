defmodule MiwayCreditCore.Repo.Migrations.CreateJournalEntries do
  @moduledoc """
  Step 14: the double-entry journal header. Insert-only — no update
  changeset is ever exposed, same immutability posture as
  AccountingEntry (see Accounting.GeneralLedger).
  """

  use Ecto.Migration

  def change do
    create table(:journal_entries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :organisation_id, references(:organisations, type: :binary_id), null: false
      add :description, :string, null: false
      add :source_type, :string, null: false
      add :source_id, :binary_id
      add :occurred_at, :utc_datetime, null: false
      add :recorded_by_id, references(:users)

      timestamps(updated_at: false)
    end

    create index(:journal_entries, [:organisation_id])
    create index(:journal_entries, [:source_type, :source_id])
  end
end
