defmodule MiwayCreditCore.Repo.Migrations.AddOrganisationIdToExistingTables do
  use Ecto.Migration

  @tables ~w(
    customers
    loan_applications
    loan_accounts
    repayment_schedule_installments
    payment_transactions
    payment_allocations
    accounting_entries
    collaterals
    audit_logs
  )a

  # Nullable for now — the next migration backfills every existing row,
  # then a final migration sets null: false. Same additive-then-backfill
  # pattern as Step 4's role split.
  def change do
    for table_name <- @tables do
      alter table(table_name) do
        add :organisation_id, references(:organisations, type: :binary_id)
      end

      create index(table_name, [:organisation_id])
    end
  end
end
