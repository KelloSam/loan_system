defmodule MiwayCreditCore.Collections.RestructuringRequest do
  @moduledoc """
  A request to extend a loan account's remaining term — the only
  restructuring lever this system offers, since a customer asking for
  smaller payments and a customer asking for more time are the same
  underlying move on a fixed-rate amortized loan. Real maker-checker:
  the approver can never be the requester (see
  `MiwayCreditCore.Collections.approve_restructuring/2`), same guard
  `MiwayCreditCore.Applications.check_separation_of_duties/3` already
  uses for application approval.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(pending approved rejected)

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "restructuring_requests" do
    field :additional_term_months, :integer
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
    |> cast(attrs, [:organisation_id, :loan_account_id, :requested_by_id, :additional_term_months, :reason])
    |> validate_required([:organisation_id, :loan_account_id, :requested_by_id, :additional_term_months, :reason])
    |> validate_number(:additional_term_months, greater_than: 0)
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
