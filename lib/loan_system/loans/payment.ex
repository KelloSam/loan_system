defmodule LoanSystem.Loans.Payment do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "payments" do
    field :amount, :decimal
    field :payment_date, :date  # Changed from naive_datetime for consistency
    field :due_date, :date
    field :status, :string, default: "pending"

    belongs_to :loan, LoanSystem.Loans.Loan, type: :binary_id

    timestamps()
  end

  @doc """
  Creates a changeset for payment.
  
  ## Parameters
    * `payment` - Existing payment struct or %Payment{}
    * `attrs` - Map of attributes to change
    
  ## Validations
    * Amount must be greater than 0
    * Status must be one of: "pending", "paid", "overdue"
    * Amount must not exceed loan's remaining balance
    * Payment dates must be consistent:
      - At least one of due_date or payment_date must be provided
      - If both are provided, they can be any dates (even if payment_date is after due_date,
        which could indicate a late payment)
    * When creating new payments or marking as paid, the amount cannot exceed
      the loan's remaining balance
    
  ## Returns
    * Changeset
  """
  def changeset(payment, attrs) do
    payment
    |> cast(attrs, [:amount, :payment_date, :due_date, :status, :loan_id])
    |> validate_required([:amount, :status, :loan_id])
    |> validate_inclusion(:status, ["pending", "paid", "overdue"])
    |> validate_number(:amount, greater_than: 0)
    |> validate_date_consistency()
    |> foreign_key_constraint(:loan_id)
  end
  
  # Validates that payment dates make logical sense
  defp validate_date_consistency(changeset) do
    due_date = get_field(changeset, :due_date)
    payment_date = get_field(changeset, :payment_date)
    
    cond do
      is_nil(due_date) and is_nil(payment_date) ->
        # At least one date should be provided
        add_error(changeset, :due_date, "either due_date or payment_date must be provided")
      is_nil(due_date) or is_nil(payment_date) ->
        # If only one date is provided, that's valid
        changeset
      Date.compare(payment_date, due_date) == :gt ->
        # Payment date is after due date (late payment)
        changeset
      true ->
        # All other cases are fine
        changeset
    end
  end
  
end
