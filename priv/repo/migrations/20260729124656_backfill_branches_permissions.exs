defmodule MiwayCreditCore.Repo.Migrations.BackfillBranchesPermissions do
  @moduledoc """
  branches.view/.manage are new entries in the permission catalog. New
  organisations get them automatically via
  Authorization.seed_default_roles/2; every pre-existing Role row does
  not, until backfilled here — same pattern as every prior
  permission-key addition (see backfill_collections_permissions.exs).
  """

  use Ecto.Migration

  @view_tier ~w(branches.view)
  @manage_tier ~w(branches.manage)

  def up do
    Enum.each(@view_tier, fn key ->
      execute("""
      INSERT INTO role_permissions (id, role_id, permission_key, inserted_at)
      SELECT gen_random_uuid(), id, '#{key}', now()
      FROM roles
      ON CONFLICT (role_id, permission_key) DO NOTHING
      """)
    end)

    Enum.each(@manage_tier, fn key ->
      execute("""
      INSERT INTO role_permissions (id, role_id, permission_key, inserted_at)
      SELECT gen_random_uuid(), id, '#{key}', now()
      FROM roles
      WHERE name IN ('platform_administrator', 'organisation_administrator')
      ON CONFLICT (role_id, permission_key) DO NOTHING
      """)
    end)
  end

  def down do
    :ok
  end
end
