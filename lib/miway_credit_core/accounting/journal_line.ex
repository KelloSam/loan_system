defmodule MiwayCreditCore.Accounting.JournalLine do
  @moduledoc """
  One debit or credit against one chart-of-accounts `Account`, part of
  a balanced `JournalEntry`. Exactly one of `debit_amount`/`credit_amount`
  is set on any given line — a line that is both or neither isn't a
  real accounting entry.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "journal_lines" do
    field :debit_amount, :decimal
    field :credit_amount, :decimal

    belongs_to :organisation, MiwayCreditCore.Organisations.Organisation, type: :binary_id
    belongs_to :journal_entry, MiwayCreditCore.Accounting.JournalEntry, type: :binary_id
    belongs_to :account, MiwayCreditCore.Accounting.Account, type: :binary_id

    timestamps(updated_at: false)
  end

  def changeset(journal_line, attrs) do
    journal_line
    |> cast(attrs, [:organisation_id, :journal_entry_id, :account_id, :debit_amount, :credit_amount])
    |> validate_required([:organisation_id, :journal_entry_id, :account_id])
    |> validate_number(:debit_amount, greater_than: 0)
    |> validate_number(:credit_amount, greater_than: 0)
    |> validate_exactly_one_side()
    |> foreign_key_constraint(:organisation_id)
    |> foreign_key_constraint(:journal_entry_id)
    |> foreign_key_constraint(:account_id)
  end

  defp validate_exactly_one_side(changeset) do
    debit = get_field(changeset, :debit_amount)
    credit = get_field(changeset, :credit_amount)

    cond do
      is_nil(debit) and is_nil(credit) ->
        add_error(changeset, :debit_amount, "either debit_amount or credit_amount is required")

      not is_nil(debit) and not is_nil(credit) ->
        add_error(changeset, :debit_amount, "a line cannot have both a debit and a credit")

      true ->
        changeset
    end
  end
end
