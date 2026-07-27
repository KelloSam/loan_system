defmodule MiwayCreditCore.Repo.Migrations.BackfillOrganisationId do
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

  # All data predating multi-tenancy belongs to the same single
  # original tenant — a flat UPDATE per table is correct here, not a
  # derived join, since there's nothing to derive from yet.
  def up do
    org_id = Ecto.UUID.generate()
    settings_id = Ecto.UUID.generate()

    execute("""
    INSERT INTO organisations (id, name, status, inserted_at, updated_at)
    VALUES ('#{org_id}', 'Miway', 'active', now(), now())
    """)

    execute("""
    INSERT INTO organisation_settings (id, organisation_id, currency, timezone, inserted_at, updated_at)
    VALUES ('#{settings_id}', '#{org_id}', 'ZMW', 'Africa/Lusaka', now(), now())
    """)

    for table <- @tables do
      execute("UPDATE #{table} SET organisation_id = '#{org_id}'")
    end
  end

  def down do
    :ok
  end
end
