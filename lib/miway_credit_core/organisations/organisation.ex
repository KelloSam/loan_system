defmodule MiwayCreditCore.Organisations.Organisation do
  @moduledoc "A tenant — one lending operation hosted on Miway CreditCore."

  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(active suspended)

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "organisations" do
    field :name, :string
    field :status, :string, default: "active"

    timestamps()
  end

  def changeset(organisation, attrs) do
    organisation
    |> cast(attrs, [:name, :status])
    |> validate_required([:name])
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint(:name)
  end
end
