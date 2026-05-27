# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#

alias LoanSystem.Accounts

# Create admin user
{:ok, _admin} = Accounts.create_user(%{
  email: "admin@example.com",
  password: "admin12345",
  role: "admin"
})

# Create a test client user
{:ok, _client} = Accounts.create_user(%{
  email: "client@example.com",
  password: "client12345",
  role: "client"
})

IO.puts "Database seeded successfully!"
