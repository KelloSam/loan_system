defmodule MiwayCreditCore.Seeds.AddTestAccounts do
  alias MiwayCreditCore.Accounts

  def run do
    # Add admin account
    case Accounts.get_user_by_email("admin@example.com") do
      nil ->
        # create_user_with_role/1 is required here — create_user/1's
        # changeset never casts :role, so it would silently create a
        # "client" regardless of what's passed.
        {:ok, admin} = Accounts.create_user_with_role(%{
          email: "admin@example.com",
          password: "Admin123456!",
          role: "admin"
        })
        IO.puts("Admin account created: #{admin.email}")
      user ->
        IO.puts("Admin account already exists: #{user.email}")
    end

    # Add client account
    case Accounts.get_user_by_email("client@example.com") do
      nil ->
        {:ok, client} = Accounts.create_user(%{
          email: "client@example.com",
          password: "Client123456!"
        })
        IO.puts("Client account created: #{client.email}")
      user ->
        IO.puts("Client account already exists: #{user.email}")
    end

    IO.puts("Test accounts setup complete!")
  end
end

# Run the seed script
MiwayCreditCore.Seeds.AddTestAccounts.run()

