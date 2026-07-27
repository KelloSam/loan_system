defmodule MiwayCreditCore.Applications.Collateral do
  @moduledoc """
  An item pledged as security against a loan — a vehicle, land title,
  electronics, etc. Deliberately simple: type, description, and an
  estimated value. No status/workflow or document upload for now.

  Attaches only to an approved LoanAccount, never to a pending
  LoanApplication — collateral secures a granted loan, not a mere
  request (confirmed product decision).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @types ~w(vehicle land electronics other)

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "collaterals" do
    field :type, :string
    field :description, :string
    field :estimated_value, :decimal

    belongs_to :organisation, MiwayCreditCore.Organisations.Organisation, type: :binary_id
    belongs_to :loan_account, MiwayCreditCore.Lending.LoanAccount, type: :binary_id

    timestamps()
  end

  def changeset(collateral, attrs) do
    collateral
    |> cast(attrs, [:organisation_id, :type, :description, :estimated_value, :loan_account_id])
    |> validate_required([:organisation_id, :type, :description, :estimated_value, :loan_account_id])
    |> validate_inclusion(:type, @types)
    |> validate_number(:estimated_value, greater_than: 0)
    |> foreign_key_constraint(:organisation_id)
    |> foreign_key_constraint(:loan_account_id)
  end
end
