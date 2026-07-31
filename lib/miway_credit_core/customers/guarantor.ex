defmodule MiwayCreditCore.Customers.Guarantor do
  @moduledoc """
  Someone who has agreed to guarantee this customer's loans. Recorded
  once at the customer level and reusable across that customer's
  future applications, not re-entered per application (confirmed
  scope decision for Step 7 — Step 9's application-level guarantor
  requirements will reference these records rather than re-modeling
  guarantors from scratch).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @id_types ~w(nrc passport company_registration)

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "guarantors" do
    field :name, :string
    field :relationship, :string
    field :phone, :string
    field :id_type, :string
    field :id_number, :string
    field :address_line, :string

    belongs_to :organisation, MiwayCreditCore.Organisations.Organisation, type: :binary_id
    belongs_to :customer, MiwayCreditCore.Customers.Customer, type: :binary_id

    timestamps()
  end

  def changeset(guarantor, attrs) do
    guarantor
    |> cast(attrs, [
      :organisation_id,
      :customer_id,
      :name,
      :relationship,
      :phone,
      :id_type,
      :id_number,
      :address_line
    ])
    |> validate_required([
      :organisation_id,
      :customer_id,
      :name,
      :relationship,
      :phone,
      :id_type,
      :id_number
    ])
    |> validate_inclusion(:id_type, @id_types)
    |> foreign_key_constraint(:organisation_id)
    |> foreign_key_constraint(:customer_id)
  end
end
