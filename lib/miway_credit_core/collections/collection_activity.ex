defmodule MiwayCreditCore.Collections.CollectionActivity do
  @moduledoc """
  One contact attempt or note against a `CollectionCase` — the
  chronological customer-communication history, and, filtered by a
  future `follow_up_date`, the pending follow-up queue. One entity for
  both rather than two parallel schemas for what's really the same
  thing viewed two ways. Insert-only — never edited or deleted, same
  posture as `AccountingEntry`/`ApprovalDecision`; a correction is a
  new activity, not an edit to an old one.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @activity_types ~w(call sms email visit letter other)
  @outcomes ~w(reached no_answer promised_payment disputed refused other)

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "collection_activities" do
    field :activity_type, :string
    field :outcome, :string
    field :notes, :string
    field :occurred_at, :utc_datetime
    field :follow_up_date, :date

    belongs_to :organisation, MiwayCreditCore.Organisations.Organisation, type: :binary_id
    belongs_to :collection_case, MiwayCreditCore.Collections.CollectionCase, type: :binary_id
    belongs_to :recorded_by, MiwayCreditCore.Accounts.User

    timestamps(updated_at: false)
  end

  def changeset(activity, attrs) do
    activity
    |> cast(attrs, [
      :organisation_id,
      :collection_case_id,
      :activity_type,
      :outcome,
      :notes,
      :occurred_at,
      :follow_up_date,
      :recorded_by_id
    ])
    |> validate_required([
      :organisation_id,
      :collection_case_id,
      :activity_type,
      :outcome,
      :occurred_at,
      :recorded_by_id
    ])
    |> validate_inclusion(:activity_type, @activity_types)
    |> validate_inclusion(:outcome, @outcomes)
    |> foreign_key_constraint(:organisation_id)
    |> foreign_key_constraint(:collection_case_id)
    |> foreign_key_constraint(:recorded_by_id)
  end
end
