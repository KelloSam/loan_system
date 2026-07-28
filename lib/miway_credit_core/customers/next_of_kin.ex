defmodule MiwayCreditCore.Customers.NextOfKin do
  @moduledoc """
  A contact to reach if the customer can't be reached directly. Just
  contact info, no evidentiary weight — hard-deletable, unlike
  KycDocument/Consent.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "next_of_kins" do
    field :name, :string
    field :relationship, :string
    field :phone, :string
    field :address_line, :string

    belongs_to :organisation, MiwayCreditCore.Organisations.Organisation, type: :binary_id
    belongs_to :customer, MiwayCreditCore.Customers.Customer, type: :binary_id

    timestamps()
  end

  def changeset(next_of_kin, attrs) do
    next_of_kin
    |> cast(attrs, [:organisation_id, :customer_id, :name, :relationship, :phone, :address_line])
    |> validate_required([:organisation_id, :customer_id, :name, :relationship, :phone])
    |> foreign_key_constraint(:organisation_id)
    |> foreign_key_constraint(:customer_id)
  end
end
