defmodule MiwayCreditCore.Organisations.Department do
  @moduledoc """
  A functional grouping of staff within an Organisation (e.g. Credit,
  Collections) — org-wide, not branch-scoped, since departments
  typically cut across branches.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "departments" do
    field :name, :string

    belongs_to :organisation, MiwayCreditCore.Organisations.Organisation, type: :binary_id

    timestamps()
  end

  def changeset(department, attrs) do
    department
    |> cast(attrs, [:organisation_id, :name])
    |> validate_required([:organisation_id, :name])
    |> unique_constraint([:organisation_id, :name])
    |> foreign_key_constraint(:organisation_id)
  end
end
