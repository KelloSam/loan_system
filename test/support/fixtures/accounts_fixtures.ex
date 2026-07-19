defmodule LoanSystem.AccountsFixtures do
  @moduledoc "Test helpers for creating LoanSystem.Accounts entities."

  def valid_user_email, do: "user#{System.unique_integer([:positive])}@example.com"
  def valid_user_password, do: "SuperSecret123"

  def valid_user_attrs(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: valid_user_email(),
      password: valid_user_password()
    })
  end

  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_attrs()
      |> LoanSystem.Accounts.create_user()

    user
  end

  def admin_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_attrs()
      |> Map.put(:role, "admin")
      |> LoanSystem.Accounts.create_user_with_role()

    user
  end
end
