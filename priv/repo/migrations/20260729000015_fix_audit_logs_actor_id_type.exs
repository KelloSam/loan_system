defmodule MiwayCreditCore.Repo.Migrations.FixAuditLogsActorIdType do
  @moduledoc """
  `audit_logs.actor_id` was created as `:binary_id`, but every real
  caller in this app passes `conn.assigns.current_user.id` —
  `Accounts.User`'s primary key, which is a plain integer (the one
  table that predates this codebase's binary_id convention). An
  integer can never cast into a binary_id column, so `AuditLogs.log/2`
  (which always returns `:ok` even when the insert fails) has been
  silently dropping the actor on every single audited event since
  audit logging was introduced — nothing has actually recorded who did
  what. No real data is lost by this migration: no row could ever have
  had a valid actor_id under the old type.
  """

  use Ecto.Migration

  def change do
    alter table(:audit_logs) do
      remove :actor_id, :binary_id
      add :actor_id, :integer
    end
  end
end
