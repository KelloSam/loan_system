defmodule MiwayCreditCore.Collections.CollectionCase do
  @moduledoc """
  The org's active effort to collect on one delinquent `LoanAccount`.
  Opened automatically the first time the account has any overdue
  installment (see `MiwayCreditCore.Collections.ensure_case_opened/2`,
  called from `MiwayCreditCore.Lending.Schedule.flip_to_overdue/1`) —
  at most one open case per account at a time.

  `recovery_status` is a property of this case (the collection
  effort), not of the loan account itself — see
  `MiwayCreditCore.Collections.set_recovery_status/3`, which flips the
  account to `"defaulted"` when recovery escalates to `"legal_action"`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(open in_progress resolved escalated closed)
  @recovery_statuses ~w(none in_recovery legal_action recovered abandoned)

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "collection_cases" do
    field :status, :string, default: "open"
    field :recovery_status, :string, default: "none"
    field :opened_at, :utc_datetime
    field :closed_at, :utc_datetime
    field :close_reason, :string

    belongs_to :organisation, MiwayCreditCore.Organisations.Organisation, type: :binary_id
    belongs_to :loan_account, MiwayCreditCore.Lending.LoanAccount, type: :binary_id
    belongs_to :customer, MiwayCreditCore.Customers.Customer, type: :binary_id
    belongs_to :assigned_to, MiwayCreditCore.Accounts.User
    belongs_to :opened_by, MiwayCreditCore.Accounts.User

    has_many :collection_activities, MiwayCreditCore.Collections.CollectionActivity
    has_many :promises_to_pay, MiwayCreditCore.Collections.PromiseToPay

    timestamps()
  end

  def changeset(collection_case, attrs) do
    collection_case
    |> cast(attrs, [
      :organisation_id,
      :loan_account_id,
      :customer_id,
      :status,
      :recovery_status,
      :assigned_to_id,
      :opened_at,
      :opened_by_id,
      :closed_at,
      :close_reason
    ])
    |> validate_required([
      :organisation_id,
      :loan_account_id,
      :customer_id,
      :status,
      :recovery_status,
      :opened_at
    ])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:recovery_status, @recovery_statuses)
    |> foreign_key_constraint(:organisation_id)
    |> foreign_key_constraint(:loan_account_id)
    |> foreign_key_constraint(:customer_id)
    |> foreign_key_constraint(:assigned_to_id)
    |> foreign_key_constraint(:opened_by_id)
  end
end
