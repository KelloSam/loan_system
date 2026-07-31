defmodule MiwayCreditCore.Accounting.JournalEntry do
  @moduledoc """
  The header of one balanced double-entry posting — two or more
  `JournalLine`s whose debits sum to their credits, enforced by
  `MiwayCreditCore.Accounting.GeneralLedger.post_journal_entry/3` before
  either is ever inserted. Insert-only, same as `AccountingEntry` — no
  update changeset is exposed anywhere in this module or
  `GeneralLedger`; a mistaken posting is reversed
  (`GeneralLedger.post_reversal/3`), never edited or deleted.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "journal_entries" do
    field :description, :string
    field :source_type, :string
    field :source_id, :binary_id
    field :occurred_at, :utc_datetime

    belongs_to :organisation, MiwayCreditCore.Organisations.Organisation, type: :binary_id
    belongs_to :recorded_by, MiwayCreditCore.Accounts.User

    has_many :journal_lines, MiwayCreditCore.Accounting.JournalLine

    timestamps(updated_at: false)
  end

  def changeset(journal_entry, attrs) do
    journal_entry
    |> cast(attrs, [
      :organisation_id,
      :description,
      :source_type,
      :source_id,
      :occurred_at,
      :recorded_by_id
    ])
    |> validate_required([:organisation_id, :description, :source_type, :occurred_at])
    |> foreign_key_constraint(:organisation_id)
    |> foreign_key_constraint(:recorded_by_id)
  end
end
