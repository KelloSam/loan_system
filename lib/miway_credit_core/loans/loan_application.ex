defmodule MiwayCreditCore.Loans.LoanApplication do
  @moduledoc """
  The request and the decision made on it. Holds nothing about money
  actually moving — that starts only once a LoanAccount exists.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(pending approved rejected withdrawn)
  @risk_levels ~w(low medium high)

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "loan_applications" do
    field :requested_amount, :decimal
    field :requested_term_months, :integer
    field :purpose, :string

    field :risk_level, :string, default: "low"
    field :risk_score, :integer

    field :status, :string, default: "pending"
    field :decided_at, :utc_datetime
    field :rejection_reason, :string

    belongs_to :customer, MiwayCreditCore.Customers.Customer, type: :binary_id
    belongs_to :decided_by, MiwayCreditCore.Accounts.User
    has_one :loan_account, MiwayCreditCore.Lending.LoanAccount

    timestamps()
  end

  @doc "Changeset for the initial application submission — status is always pending."
  def changeset(loan_application, attrs) do
    loan_application
    |> cast(attrs, [:customer_id, :requested_amount, :requested_term_months, :purpose,
                   :risk_level, :risk_score])
    |> validate_required([:customer_id, :requested_amount, :requested_term_months])
    |> validate_inclusion(:risk_level, @risk_levels)
    |> validate_number(:requested_amount, greater_than: 0)
    |> validate_number(:requested_term_months, greater_than: 0)
    |> validate_length(:purpose, max: 500, message: "must be less than 500 characters")
    |> foreign_key_constraint(:customer_id)
  end

  @doc "Changeset for deciding a pending application (approve/reject/withdraw)."
  def decision_changeset(loan_application, attrs) do
    loan_application
    |> cast(attrs, [:status, :decided_at, :decided_by_id, :rejection_reason])
    |> validate_required([:status, :decided_at])
    |> validate_inclusion(:status, @statuses)
    |> validate_rejection_reason()
    |> foreign_key_constraint(:decided_by_id)
  end

  defp validate_rejection_reason(changeset) do
    if get_field(changeset, :status) == "rejected" do
      validate_required(changeset, [:rejection_reason])
    else
      changeset
    end
  end
end
