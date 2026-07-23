defmodule MiwayCreditCore.Loans.Loan do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "loans" do
    field :amount, :decimal
    field :interest_rate, :decimal
    field :term_months, :integer
    field :status, :string, default: "pending"
    field :approved_at, :naive_datetime
    field :next_payment_date, :date
    field :remaining_balance, :decimal
    field :purpose, :string
    field :risk_level, :string, default: "low"

    belongs_to :client, MiwayCreditCore.Clients.Client, type: :binary_id
    has_many :payments, MiwayCreditCore.Loans.Payment, preload_order: [asc: :due_date]
    has_many :collaterals, MiwayCreditCore.Loans.Collateral

    timestamps()
  end

  @doc """
  Creates a changeset for loan.
  
  ## Parameters
    * `loan` - Existing loan struct or %Loan{}
    * `attrs` - Map of attributes to change
    
  ## Validations
    * Required fields: amount, interest_rate, term_months, status, remaining_balance, client_id
    * Status must be one of: "pending", "approved", "rejected", "completed"
    * Numerical validations:
      - amount must be > 0
      - term_months must be > 0
      - interest_rate must be > 0
      - remaining_balance must be >= 0
    * Purpose field has max length of 500 characters
    * When status is "approved", next_payment_date must be on or after the approval date
  
  ## Returns
    * Changeset
  """
  def changeset(loan, attrs) do
    loan
    |> cast(attrs, [:amount, :interest_rate, :term_months, :status, :approved_at,
                   :next_payment_date, :remaining_balance, :client_id, :purpose, :risk_level])
    |> validate_required([:amount, :interest_rate, :term_months, :status, :remaining_balance, :client_id])
    |> validate_inclusion(:status, ["pending", "approved", "rejected", "completed"])
    |> validate_inclusion(:risk_level, ["low", "medium", "high"])
    |> validate_number(:amount, greater_than: 0)
    |> validate_number(:term_months, greater_than: 0)
    |> validate_number(:interest_rate, greater_than: 0)
    |> validate_number(:remaining_balance, greater_than_or_equal_to: 0)
    |> validate_length(:purpose, max: 500, message: "must be less than 500 characters")
    |> validate_payment_date()
    |> foreign_key_constraint(:client_id)
  end
  
  # Validates that the next_payment_date is on or after the approved_at date
  defp validate_payment_date(changeset) do
    status = get_field(changeset, :status)
    approved_at = get_field(changeset, :approved_at)
    next_payment_date = get_field(changeset, :next_payment_date)
    
    if status == "approved" && approved_at && next_payment_date do
      # Convert approved_at to Date for comparison
      approved_date = NaiveDateTime.to_date(approved_at)
      
      case Date.compare(next_payment_date, approved_date) do
        :lt -> # next_payment_date is before approved_date
          add_error(changeset, :next_payment_date, "must be after the approval date")
        _ -> # Equal or greater is fine
          changeset
      end
    else
      # Skip validation if conditions aren't met
      changeset
    end
  end
end
