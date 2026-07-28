defmodule MiwayCreditCore.Repo.Migrations.CreateCollectionCases do
  @moduledoc """
  Step 15: opened automatically the first time an account has any
  overdue installment (see Collections.ensure_case_opened/2, called
  from Lending.Schedule.flip_to_overdue/1) — at most one open case per
  account. recovery_status is a property of the org's current
  collection effort, not the loan itself; setting it to "legal_action"
  flips the account to "defaulted" (Collections.set_recovery_status/3).
  """

  use Ecto.Migration

  def change do
    create table(:collection_cases, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :organisation_id, references(:organisations, type: :binary_id), null: false
      add :loan_account_id, references(:loan_accounts, type: :binary_id), null: false
      add :customer_id, references(:customers, type: :binary_id), null: false
      add :status, :string, null: false, default: "open"
      add :recovery_status, :string, null: false, default: "none"
      add :assigned_to_id, references(:users)
      add :opened_at, :utc_datetime, null: false
      add :opened_by_id, references(:users)
      add :closed_at, :utc_datetime
      add :close_reason, :string

      timestamps()
    end

    create index(:collection_cases, [:organisation_id])
    create index(:collection_cases, [:loan_account_id])
    create index(:collection_cases, [:status])
  end
end
