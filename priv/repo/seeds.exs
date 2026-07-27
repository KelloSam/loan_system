# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#

alias MiwayCreditCore.{Accounts, Customers}

# Create the platform administrator (staff identity)
{:ok, _admin, _staff_member} = Accounts.register_staff_member(
  %{email: "admin@example.com", password: "Admin123456!"},
  "platform_administrator"
)

# Create a test customer-portal login — needs a Customer to link to first
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

{:ok, _client, _customer_user} = Accounts.register_customer_user(
  %{email: "client@example.com", password: "Client123456!"},
  customer.id
)

IO.puts "Database seeded successfully!"
