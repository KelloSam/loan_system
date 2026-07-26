defmodule MiwayCreditCore.CustomersFixtures do
  @moduledoc "Test helpers for creating MiwayCreditCore.Customers entities."

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

  def customer_fixture(attrs \\ %{}) do
    {:ok, customer} =
      attrs
      |> valid_customer_attrs()
      |> MiwayCreditCore.Customers.create_customer()

    customer
  end
end
