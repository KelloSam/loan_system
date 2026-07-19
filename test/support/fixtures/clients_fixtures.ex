defmodule LoanSystem.ClientsFixtures do
  @moduledoc "Test helpers for creating LoanSystem.Clients entities."

  @doc "A phone number matching the '26' or '260' + 7+ digits format the schema requires."
  def valid_client_phone do
    n = System.unique_integer([:positive]) |> rem(9_999_999) |> abs()
    "260" <> (n |> Integer.to_string() |> String.pad_leading(7, "0"))
  end

  def valid_client_id_number do
    n = System.unique_integer([:positive])
    "#{n}/78/9"
  end

  def valid_client_attrs(attrs \\ %{}) do
    Enum.into(attrs, %{
      name: "Test Client #{System.unique_integer([:positive])}",
      phone: valid_client_phone(),
      id_number: valid_client_id_number()
    })
  end

  def client_fixture(attrs \\ %{}) do
    {:ok, client} =
      attrs
      |> valid_client_attrs()
      |> LoanSystem.Clients.create_client()

    client
  end
end
