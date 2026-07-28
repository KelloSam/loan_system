defmodule MiwayCreditCore.Repo.Migrations.CreateJournalLines do
  @moduledoc """
  Step 14: one debit or credit against one chart-of-accounts account.
  A JournalEntry is balanced when its lines' debits sum to its
  credits' sum — enforced in Accounting.GeneralLedger.post_journal_entry/3
  before any row is written, not at the database layer.
  """

  use Ecto.Migration

  def change do
    create table(:journal_lines, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :organisation_id, references(:organisations, type: :binary_id), null: false
      add :journal_entry_id, references(:journal_entries, type: :binary_id), null: false
      add :account_id, references(:accounts, type: :binary_id), null: false
      add :debit_amount, :decimal
      add :credit_amount, :decimal

      timestamps(updated_at: false)
    end

    create index(:journal_lines, [:journal_entry_id])
    create index(:journal_lines, [:account_id])
  end
end
