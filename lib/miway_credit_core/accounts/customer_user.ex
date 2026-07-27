defmodule MiwayCreditCore.Accounts.CustomerUser do
  @moduledoc """
  The customer-portal login relationship — links a login `User` to the
  `Customer` (borrower) business record it may act as. A real
  foreign-key join, replacing the old email-string matching between
  `users.email` and `customers.email`.

  One User maps to exactly one Customer (unique on `user_id`); a
  Customer isn't restricted to one portal login (not unique on
  `customer_id`) — a business customer could have more than one staff
  member with portal access later.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "customer_users" do
    belongs_to :user, MiwayCreditCore.Accounts.User
    belongs_to :customer, MiwayCreditCore.Customers.Customer, type: :binary_id

    timestamps()
  end

  def changeset(customer_user, attrs) do
    customer_user
    |> cast(attrs, [:user_id, :customer_id])
    |> validate_required([:user_id, :customer_id])
    |> unique_constraint(:user_id)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:customer_id)
  end
end
