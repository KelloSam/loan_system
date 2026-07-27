defmodule MiwayCreditCore.Repo.Migrations.MakeOrganisationIdRequired do
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

  def change do
    for table_name <- @tables do
      alter table(table_name) do
        modify :organisation_id, :binary_id, null: false
      end
    end
  end
end
