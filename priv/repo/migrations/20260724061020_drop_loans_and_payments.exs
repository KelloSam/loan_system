defmodule MiwayCreditCore.Repo.Migrations.DropLoansAndPayments do
  use Ecto.Migration

  # Confirmed with the project owner: the `loans` / `payments` tables
  # hold only dev/seed data, nothing worth a backfill migration. Their
  # responsibilities are now fully covered by loan_applications,
  # loan_accounts, repayment_schedule_installments, payment_transactions,
  # payment_allocations, and accounting_entries.
  def change do
    drop table(:payments)
    drop table(:loans)
  end
end
