defmodule MiwayCreditCore.Seeds.AddTestAccounts do
  alias MiwayCreditCore.{Accounts, Customers, Organisations}
  alias MiwayCreditCore.Organisations.Organisation
  alias MiwayCreditCore.Accounts.Scope
  alias MiwayCreditCore.Repo

  def run do
    organisation =
      Repo.get_by(Organisation, name: "Miway") ||
        (
          {:ok, organisation} = Organisations.create_organisation(%{name: "Miway"})
          organisation
        )

    case Accounts.get_user_by_email("admin@example.com") do
      nil ->
        {:ok, admin, _staff_member} =
          Accounts.register_staff_member(
            %{email: "admin@example.com", password: "Admin123456!"},
            "platform_administrator"
          )

        IO.puts("Admin account created: #{admin.email} (platform_administrator, no organisation membership needed)")

      user ->
        IO.puts("Admin account already exists: #{user.email}")
    end

    ensure_staff_member("orgadmin@example.com", "OrgAdmin123456!", "organisation_administrator", organisation)
    ensure_staff_member("loanofficer@example.com", "LoanOfficer123456!", "loan_officer", organisation)

    case Accounts.get_user_by_email("client@example.com") do
      nil ->
        customer =
          Customers.get_customer_by_email("client@example.com") ||
            (
              {:ok, customer} =
                Customers.create_customer(%Scope{organisation_id: organisation.id}, %{
                  name: "Demo Client",
                  phone: "260970000000",
                  id_number: "999999/99/9",
                  email: "client@example.com",
                  address: "Lusaka",
                  active: true
                })

              customer
            )

        {:ok, client, _customer_user} =
          Accounts.register_customer_user(
            %{email: "client@example.com", password: "Client123456!"},
            customer.id
          )

        IO.puts("Client account created: #{client.email}")

      user ->
        IO.puts("Client account already exists: #{user.email}")
    end

    IO.puts("Test accounts setup complete!")
  end

  defp ensure_staff_member(email, password, role, organisation) do
    case Accounts.get_user_by_email(email) do
      nil ->
        {:ok, user, staff_member} = Accounts.register_staff_member(%{email: email, password: password}, role)
        {:ok, _membership} = Organisations.add_staff_to_organisation(staff_member.id, organisation.id)
        IO.puts("#{role} account created: #{user.email}, linked to #{organisation.name}")

      user ->
        staff_member = Accounts.get_staff_member(user.id)

        unless Organisations.get_active_membership_for_staff_member(staff_member.id) do
          {:ok, _membership} = Organisations.add_staff_to_organisation(staff_member.id, organisation.id)
          IO.puts("#{email} existed without a membership — linked to #{organisation.name}")
        else
          IO.puts("#{role} account already exists: #{user.email}")
        end
    end
  end
end

# Run the seed script
MiwayCreditCore.Seeds.AddTestAccounts.run()
