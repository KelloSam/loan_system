defmodule MiwayCreditCore.Collections.PromiseToPay do
  @moduledoc """
  A customer's commitment to pay a specific amount by a specific
  date, against a `CollectionCase`. Evaluated by
  `MiwayCreditCore.Collections.evaluate_promises/0` (called from the
  existing `ArrearsScheduler` tick, not a second background process):
  once `promised_date` has passed, `"pending"` resolves to `"kept"` if
  a posted payment >= `promised_amount` arrived on the account since
  the promise was recorded, else `"broken"`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(pending kept broken)

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "promises_to_pay" do
    field :promised_amount, :decimal
    field :promised_date, :date
    field :status, :string, default: "pending"
    field :evaluated_at, :utc_datetime

    belongs_to :organisation, MiwayCreditCore.Organisations.Organisation, type: :binary_id
    belongs_to :collection_case, MiwayCreditCore.Collections.CollectionCase, type: :binary_id
    belongs_to :recorded_by, MiwayCreditCore.Accounts.User

    timestamps()
  end

  def changeset(promise, attrs) do
    promise
    |> cast(attrs, [:organisation_id, :collection_case_id, :promised_amount, :promised_date, :recorded_by_id])
    |> validate_required([:organisation_id, :collection_case_id, :promised_amount, :promised_date, :recorded_by_id])
    |> validate_number(:promised_amount, greater_than: 0)
    |> foreign_key_constraint(:organisation_id)
    |> foreign_key_constraint(:collection_case_id)
    |> foreign_key_constraint(:recorded_by_id)
  end

  def evaluation_changeset(promise, attrs) do
    promise
    |> cast(attrs, [:status, :evaluated_at])
    |> validate_required([:status, :evaluated_at])
    |> validate_inclusion(:status, @statuses)
  end
end
