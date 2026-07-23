defmodule MiwayCreditCore.Loans.Collateral do
  @moduledoc """
  An item pledged as security against a loan — a vehicle, land title,
  electronics, etc. Deliberately simple: type, description, and an
  estimated value. No status/workflow or document upload for now.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @types ~w(vehicle land electronics other)

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "collaterals" do
    field :type, :string
    field :description, :string
    field :estimated_value, :decimal

    belongs_to :loan, MiwayCreditCore.Loans.Loan, type: :binary_id

    timestamps()
  end

  def changeset(collateral, attrs) do
    collateral
    |> cast(attrs, [:type, :description, :estimated_value, :loan_id])
    |> validate_required([:type, :description, :estimated_value, :loan_id])
    |> validate_inclusion(:type, @types)
    |> validate_number(:estimated_value, greater_than: 0)
    |> foreign_key_constraint(:loan_id)
  end
end
