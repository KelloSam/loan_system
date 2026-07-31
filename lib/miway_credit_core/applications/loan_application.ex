defmodule MiwayCreditCore.Applications.LoanApplication do
  @moduledoc """
  The request and the decision made on it. Holds nothing about money
  actually moving — that starts only once a LoanAccount exists.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(pending under_review approved rejected disbursed withdrawn referred)
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

    field :assessed_at, :utc_datetime
    field :assessment_notes, :string
    field :disbursed_at, :utc_datetime

    field :conditions, :string
    field :conditions_cleared_at, :utc_datetime

    belongs_to :organisation, MiwayCreditCore.Organisations.Organisation, type: :binary_id
    belongs_to :customer, MiwayCreditCore.Customers.Customer, type: :binary_id
    belongs_to :decided_by, MiwayCreditCore.Accounts.User
    belongs_to :created_by, MiwayCreditCore.Accounts.User
    belongs_to :assessed_by, MiwayCreditCore.Accounts.User
    belongs_to :disbursed_by, MiwayCreditCore.Accounts.User
    belongs_to :loan_product, MiwayCreditCore.Products.LoanProduct, type: :binary_id
    has_one :loan_account, MiwayCreditCore.Lending.LoanAccount

    has_many :approval_decisions, MiwayCreditCore.Applications.ApprovalDecision,
      preload_order: [asc: :level, asc: :inserted_at]

    timestamps()
  end

  @doc """
  Changeset for the initial application submission — status is always
  pending. `organisation_id` is cast here, but Applications.create_application/2
  always computes and overwrites it from the customer being applied for
  before this ever runs — never taken as-is from raw caller input, so
  an application can't be filed under a different organisation than
  its own customer. `created_by_id` records who submitted it, checked
  against the deciding user at approve/reject time (maker-checker) —
  nullable, since it's optional information about the past, not a
  structural invariant.
  """
  def changeset(loan_application, attrs) do
    loan_application
    |> cast(attrs, [
      :organisation_id,
      :customer_id,
      :created_by_id,
      :loan_product_id,
      :requested_amount,
      :requested_term_months,
      :purpose,
      :risk_level,
      :risk_score
    ])
    |> validate_required([
      :organisation_id,
      :customer_id,
      :loan_product_id,
      :requested_amount,
      :requested_term_months
    ])
    |> validate_inclusion(:risk_level, @risk_levels)
    |> validate_number(:requested_amount, greater_than: 0)
    |> validate_number(:requested_term_months, greater_than: 0)
    |> validate_length(:purpose, max: 500, message: "must be less than 500 characters")
    |> foreign_key_constraint(:customer_id)
    |> foreign_key_constraint(:organisation_id)
    |> foreign_key_constraint(:created_by_id)
    |> foreign_key_constraint(:loan_product_id)
  end

  @doc """
  Changeset for a lifecycle transition — assess, approve, reject,
  conditionally approve, disburse, withdraw, refer, or clear
  conditions. Each caller casts only the fields relevant to its own
  transition (e.g. assess sets assessed_at/assessed_by_id, not
  decided_at), so only :status is universally required.
  """
  def decision_changeset(loan_application, attrs) do
    loan_application
    |> cast(attrs, [
      :status,
      :decided_at,
      :decided_by_id,
      :rejection_reason,
      :assessed_at,
      :assessed_by_id,
      :assessment_notes,
      :disbursed_at,
      :disbursed_by_id,
      :conditions,
      :conditions_cleared_at
    ])
    |> validate_required([:status])
    |> validate_inclusion(:status, @statuses)
    |> validate_rejection_reason()
    |> foreign_key_constraint(:decided_by_id)
    |> foreign_key_constraint(:assessed_by_id)
    |> foreign_key_constraint(:disbursed_by_id)
  end

  defp validate_rejection_reason(changeset) do
    if get_field(changeset, :status) == "rejected" do
      validate_required(changeset, [:rejection_reason])
    else
      changeset
    end
  end
end
