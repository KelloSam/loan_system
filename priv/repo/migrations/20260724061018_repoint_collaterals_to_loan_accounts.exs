defmodule MiwayCreditCore.Repo.Migrations.RepointCollateralsToLoanAccounts do
  use Ecto.Migration

  # Collateral now attaches only to an approved LoanAccount, never to a
  # pending LoanApplication (confirmed product decision). Existing
  # collateral rows reference the old `loans` table via `loan_id` and
  # point at data that is being dropped as part of this restructure
  # (confirmed dev/test data only, nothing worth preserving) — so this
  # truncates rather than attempting to carry rows across the schema
  # change.
  def change do
    execute "TRUNCATE TABLE collaterals", "SELECT 1"

    alter table(:collaterals) do
      remove :loan_id, references(:loans, type: :binary_id)
      add :loan_account_id, references(:loan_accounts, type: :binary_id), null: false
    end

    create index(:collaterals, [:loan_account_id])
  end
end
