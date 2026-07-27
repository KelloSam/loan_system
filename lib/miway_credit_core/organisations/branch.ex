defmodule MiwayCreditCore.Organisations.Branch do
  @moduledoc "A physical branch belonging to an Organisation."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "branches" do
    field :name, :string
    field :code, :string
    field :address, :string
    field :active, :boolean, default: true

    belongs_to :organisation, MiwayCreditCore.Organisations.Organisation, type: :binary_id

    timestamps()
  end

  def changeset(branch, attrs) do
    branch
    |> cast(attrs, [:organisation_id, :name, :code, :address, :active])
    |> validate_required([:organisation_id, :name, :code])
    |> unique_constraint([:organisation_id, :code])
    |> foreign_key_constraint(:organisation_id)
  end
end
