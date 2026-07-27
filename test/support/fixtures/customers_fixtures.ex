defmodule MiwayCreditCore.CustomersFixtures do
  @moduledoc "Test helpers for creating MiwayCreditCore.Customers entities."

  alias MiwayCreditCore.Customers
  alias MiwayCreditCore.Accounts.Scope

  @doc "A phone number matching the '26' or '260' + 7+ digits format the schema requires."
  def valid_customer_phone do
    n = System.unique_integer([:positive]) |> rem(9_999_999) |> abs()
    "260" <> (n |> Integer.to_string() |> String.pad_leading(7, "0"))
  end

  def valid_customer_id_number do
    n = System.unique_integer([:positive])
    "#{n}/78/9"
  end

  def valid_customer_attrs(attrs \\ %{}) do
    Enum.into(attrs, %{
      name: "Test Customer #{System.unique_integer([:positive])}",
      phone: valid_customer_phone(),
      id_number: valid_customer_id_number()
    })
  end

  @doc """
  Creates a customer under a fresh, throwaway organisation — fine for
  the vast majority of tests, which don't care about multi-tenancy at
  all. Tests that specifically exercise organisation isolation should
  use `customer_fixture_in_organisation/2` instead, so two customers
  can be placed in two different, known organisations.
  """
  def customer_fixture(attrs \\ %{}) do
    organisation = MiwayCreditCore.OrganisationsFixtures.organisation_fixture()
    customer_fixture_in_organisation(organisation, attrs)
  end

  def customer_fixture_in_organisation(%MiwayCreditCore.Organisations.Organisation{} = organisation, attrs \\ %{}) do
    scope = %Scope{organisation_id: organisation.id}

    {:ok, customer} =
      attrs
      |> valid_customer_attrs()
      |> then(&Customers.create_customer(scope, &1))

    customer
  end
end
