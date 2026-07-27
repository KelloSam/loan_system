defmodule MiwayCreditCore.Repo.Migrations.RelaxAuditLogsOrganisationId do
  use Ecto.Migration

  # audit_logs isn't purely organisation-owned like the other eight
  # tables — some events (a failed login for an unknown email, an
  # account lockout before any org is resolved) happen with no
  # organisation in context at all. Nullable here, unlike its siblings
  # in the previous migration, is the correct constraint, not an
  # oversight.
  def change do
    alter table(:audit_logs) do
      modify :organisation_id, :binary_id, null: true
    end
  end
end
