defmodule MiwayCreditCore.Seeds.AddTestAccounts do
  alias MiwayCreditCore.{Accounts, Customers}

  def run do
    case Accounts.get_user_by_email("admin@example.com") do
      nil ->
        {:ok, admin, _staff_member} =
          Accounts.register_staff_member(
            %{email: "admin@example.com", password: "Admin123456!"},
            "platform_administrator"
          )

        IO.puts("Admin account created: #{admin.email}")

      user ->
        IO.puts("Admin account already exists: #{user.email}")
    end

    case Accounts.get_user_by_email("client@example.com") do
      nil ->
        customer =
          Customers.get_customer_by_email("client@example.com") ||
            (
              {:ok, customer} =
                Customers.create_customer(%{
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
end

# Run the seed script
MiwayCreditCore.Seeds.AddTestAccounts.run()
