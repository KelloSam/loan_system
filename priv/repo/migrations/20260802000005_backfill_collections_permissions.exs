defmodule MiwayCreditCore.Repo.Migrations.BackfillCollectionsPermissions do
  @moduledoc """
  collections.view/.manage, write_offs.request/.approve,
  restructuring.request/.approve are new entries in the permission
  catalog. New organisations get them automatically via
  Authorization.seed_default_roles/2; every pre-existing Role row
  does not, until backfilled here — same pattern as every prior
  permission-key addition (see backfill_products_permissions.exs).
  """

  use Ecto.Migration

  @request_tier ~w(collections.view collections.manage write_offs.request restructuring.request)
  @approve_tier ~w(write_offs.approve restructuring.approve)

  def up do
    Enum.each(@request_tier, fn key ->
      execute("""
      INSERT INTO role_permissions (id, role_id, permission_key, inserted_at)
      SELECT gen_random_uuid(), id, '#{key}', now()
      FROM roles
      ON CONFLICT (role_id, permission_key) DO NOTHING
      """)
    end)

    Enum.each(@approve_tier, fn key ->
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
