defmodule MiwayCreditCore.Collections.WriteOffRequest do
  @moduledoc """
  The missing front door onto `MiwayCreditCore.Lending.write_off_account/2`,
  which previously had zero web-layer wiring, no permission gate, and
  no request/approval separation at all. Real maker-checker, same
  guard as `RestructuringRequest`. Approval calls through to the
  existing `write_off_account/2` rather than duplicating its
  balance-zeroing/ledger-posting logic.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(pending approved rejected)

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "write_off_requests" do
    field :requested_amount, :decimal
    field :reason, :string
    field :status, :string, default: "pending"
    field :decided_at, :utc_datetime
    field :decision_notes, :string

    belongs_to :organisation, MiwayCreditCore.Organisations.Organisation, type: :binary_id
    belongs_to :loan_account, MiwayCreditCore.Lending.LoanAccount, type: :binary_id
    belongs_to :requested_by, MiwayCreditCore.Accounts.User
    belongs_to :decided_by, MiwayCreditCore.Accounts.User

    timestamps()
  end

  def changeset(request, attrs) do
    request
    |> cast(attrs, [:organisation_id, :loan_account_id, :requested_by_id, :requested_amount, :reason])
    |> validate_required([:organisation_id, :loan_account_id, :requested_by_id, :requested_amount, :reason])
    |> validate_number(:requested_amount, greater_than: 0)
    |> foreign_key_constraint(:organisation_id)
    |> foreign_key_constraint(:loan_account_id)
    |> foreign_key_constraint(:requested_by_id)
  end

  def decision_changeset(request, attrs) do
    request
    |> cast(attrs, [:status, :decided_by_id, :decided_at, :decision_notes])
    |> validate_required([:status, :decided_by_id, :decided_at])
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:decided_by_id)
  end
end
