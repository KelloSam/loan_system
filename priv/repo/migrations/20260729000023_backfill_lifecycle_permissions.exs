defmodule MiwayCreditCore.Repo.Migrations.BackfillLifecyclePermissions do
  @moduledoc """
  applications.assess/.withdraw and loans.disburse are new Step 9
  entries in the permission catalog. New organisations get them
  automatically via Authorization.seed_default_roles/2; every
  pre-existing Role row does not, until backfilled here — the same
  kind of catalog-growth backfill Step 8 needed for products.view/
  .manage.
  """

  use Ecto.Migration

  def up do
    execute("""
    INSERT INTO role_permissions (id, role_id, permission_key, inserted_at)
    SELECT gen_random_uuid(), id, 'applications.assess', now()
    FROM roles
    ON CONFLICT (role_id, permission_key) DO NOTHING
    """)

    execute("""
    INSERT INTO role_permissions (id, role_id, permission_key, inserted_at)
    SELECT gen_random_uuid(), id, 'applications.withdraw', now()
    FROM roles
    ON CONFLICT (role_id, permission_key) DO NOTHING
    """)

    execute("""
    INSERT INTO role_permissions (id, role_id, permission_key, inserted_at)
    SELECT gen_random_uuid(), id, 'loans.disburse', now()
    FROM roles
    WHERE name IN ('platform_administrator', 'organisation_administrator')
    ON CONFLICT (role_id, permission_key) DO NOTHING
    """)
  end

  def down do
    :ok
  end
end
