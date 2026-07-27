defmodule MiwayCreditCore.Repo.Migrations.BackfillStaffAndCustomerUsers do
  use Ecto.Migration
  import Ecto.Query

  # Data migration: every existing users.role == "admin" becomes a
  # StaffMember (platform_administrator — the only role that existed
  # before this split); every role == "client" becomes a CustomerUser
  # if a Customer with a matching email exists. Run before the
  # following migration drops the role column.
  def up do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    admin_ids =
      from(u in "users", where: u.role == "admin", select: u.id)
      |> repo().all()

    Enum.each(admin_ids, fn user_id ->
      repo().insert_all("staff_members", [
        %{
          id: Ecto.UUID.bingenerate(),
          user_id: user_id,
          role: "platform_administrator",
          inserted_at: now,
          updated_at: now
        }
      ])
    end)

    client_users =
      from(u in "users", where: u.role == "client", select: %{id: u.id, email: u.email})
      |> repo().all()

    Enum.each(client_users, fn %{id: user_id, email: email} ->
      customer_id =
        from(c in "customers", where: c.email == ^email, select: c.id, limit: 1)
        |> repo().one()

      case customer_id do
        nil ->
          IO.warn(
            "BackfillStaffAndCustomerUsers: no Customer matches client user #{email} " <>
              "(user_id=#{user_id}) — left unlinked, needs manual CustomerUser creation"
          )

        customer_id ->
          repo().insert_all("customer_users", [
            %{
              id: Ecto.UUID.bingenerate(),
              user_id: user_id,
              customer_id: customer_id,
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
