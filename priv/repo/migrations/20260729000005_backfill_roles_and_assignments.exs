defmodule MiwayCreditCore.Repo.Migrations.BackfillRolesAndAssignments do
  use Ecto.Migration
  import Ecto.Query

  @role_names ~w(platform_administrator organisation_administrator loan_officer)

  @all_permissions ~w(
    customers.view customers.manage
    applications.view applications.create applications.edit applications.approve applications.reject
    payments.receive payments.reverse
    collateral.manage
    reports.view audit.view
  )

  @default_permissions %{
    "platform_administrator" => @all_permissions,
    "organisation_administrator" => @all_permissions,
    "loan_officer" => ~w(
      applications.create applications.view applications.edit
      payments.receive customers.manage customers.view reports.view
    )
  }

  # Organisations created before this migration (Miway, Northside —
  # both from Step 5) have no Roles at all yet. New organisations
  # created after this point get theirs automatically via
  # Authorization.provision_organisation/1; this is purely for the
  # ones that predate that function existing.
  def up do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    organisation_ids = from(o in "organisations", select: o.id) |> repo().all()

    role_id_by_org_and_name =
      for organisation_id <- organisation_ids, role_name <- @role_names, into: %{} do
        role_id = Ecto.UUID.generate()

        repo().insert_all("roles", [
          %{
            id: Ecto.UUID.dump!(role_id),
            organisation_id: organisation_id,
            name: role_name,
            inserted_at: now,
            updated_at: now
          }
        ])

        permission_rows =
          Enum.map(Map.fetch!(@default_permissions, role_name), fn permission_key ->
            %{
              id: Ecto.UUID.dump!(Ecto.UUID.generate()),
              role_id: Ecto.UUID.dump!(role_id),
              permission_key: permission_key,
              inserted_at: now
            }
          end)

        repo().insert_all("role_permissions", permission_rows)

        {{organisation_id, role_name}, role_id}
      end

    memberships =
      from(m in "organisation_memberships",
        join: s in "staff_members",
        on: s.id == m.staff_member_id,
        select: %{id: m.id, organisation_id: m.organisation_id, role: s.role}
      )
      |> repo().all()

    Enum.each(memberships, fn %{id: membership_id, organisation_id: organisation_id, role: role_name} ->
      case Map.get(role_id_by_org_and_name, {organisation_id, role_name}) do
        nil ->
          IO.warn("BackfillRolesAndAssignments: no #{role_name} role seeded for org #{organisation_id}, skipping membership #{membership_id}")

        role_id ->
          repo().insert_all("role_assignments", [
            %{
              id: Ecto.UUID.dump!(Ecto.UUID.generate()),
              organisation_membership_id: membership_id,
              role_id: Ecto.UUID.dump!(role_id),
              inserted_at: now,
              updated_at: now
            }
          ])
      end
    end)
  end

  def down do
    :ok
  end
end
