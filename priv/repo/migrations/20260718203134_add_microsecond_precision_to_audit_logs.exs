defmodule LoanSystem.Repo.Migrations.AddMicrosecondPrecisionToAuditLogs do
  use Ecto.Migration

  @moduledoc """
  inserted_at was second-precision, so audit events logged within the
  same second (e.g. a script or a fast admin action) sort non-
  deterministically under list_recent/1's ORDER BY inserted_at DESC —
  ties get whatever order Postgres happens to return, not insertion
  order. Ordering genuinely matters for an audit trail.
  """

  def change do
    alter table(:audit_logs) do
      modify :inserted_at, :naive_datetime_usec, from: :naive_datetime
    end
  end
end
