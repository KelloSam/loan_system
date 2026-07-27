defmodule MiwayCreditCore.Organisations.OrganisationSettings do
  @moduledoc """
  Org-wide configuration, 1:1 with Organisation. Deliberately minimal
  today — extended when Step 6 (approval limits) or Step 8 (loan
  products) actually need an org-level knob, not speculatively now.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "organisation_settings" do
    field :currency, :string, default: "ZMW"
    field :timezone, :string, default: "Africa/Lusaka"

    belongs_to :organisation, MiwayCreditCore.Organisations.Organisation, type: :binary_id

    timestamps()
  end

  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [:organisation_id, :currency, :timezone])
    |> validate_required([:organisation_id, :currency, :timezone])
    |> unique_constraint(:organisation_id)
    |> foreign_key_constraint(:organisation_id)
  end
end
