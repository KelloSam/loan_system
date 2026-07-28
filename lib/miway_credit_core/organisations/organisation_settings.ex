defmodule MiwayCreditCore.Organisations.OrganisationSettings do
  @moduledoc """
  Org-wide configuration, 1:1 with Organisation. Deliberately minimal
  today — extended when Step 6 (approval limits) or Step 8 (loan
  products) actually need an org-level knob, not speculatively now.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @allocation_components ~w(penalty interest principal)

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "organisation_settings" do
    field :currency, :string, default: "ZMW"
    field :timezone, :string, default: "Africa/Lusaka"
    field :allocation_order, {:array, :string}, default: ~w(penalty interest principal)

    belongs_to :organisation, MiwayCreditCore.Organisations.Organisation, type: :binary_id

    timestamps()
  end

  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [:organisation_id, :currency, :timezone, :allocation_order])
    |> validate_required([:organisation_id, :currency, :timezone, :allocation_order])
    |> validate_subset(:allocation_order, @allocation_components)
    |> unique_constraint(:organisation_id)
    |> foreign_key_constraint(:organisation_id)
  end
end
