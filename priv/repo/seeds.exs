# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#

alias MiwayCreditCore.Accounts

# Create admin user — create_user_with_role/1 is required here;
# create_user/1's changeset never casts :role, so it would silently
# create a "client" regardless of what's passed.
{:ok, _admin} = Accounts.create_user_with_role(%{
  email: "admin@example.com",
  password: "Admin123456!",
  role: "admin"
})

# Create a test client user
{:ok, _client} = Accounts.create_user(%{
  email: "client@example.com",
  password: "Client123456!"
})

IO.puts "Database seeded successfully!"
