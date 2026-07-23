defmodule MiwayCreditCore.Seeds.AddTestAccounts do
  alias MiwayCreditCore.Accounts

  def run do
    # Add admin account
    case Accounts.get_user_by_email("admin@example.com") do
      nil ->
        {:ok, admin} = Accounts.create_user(%{
          email: "admin@example.com",
          password: "admin12345",
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
          password: "client12345",
          role: "client"
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

