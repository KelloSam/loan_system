defmodule MiwayCreditCore.Repo.Migrations.DropRoleFromUsers do
  use Ecto.Migration

  # Role now lives on StaffMember (employee identity) or is implied by
  # CustomerUser (portal identity) — see the backfill migration just
  # before this one. Kept reversible: `remove` here restores the
  # column (not the data) on rollback.
  def change do
    alter table(:users) do
      remove :role, :string, default: "client", null: false
    end
  end
end
