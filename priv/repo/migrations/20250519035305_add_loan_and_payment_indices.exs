defmodule LoanSystem.Repo.Migrations.AddLoanAndPaymentIndices do
  use Ecto.Migration
  def change do
    # Add index for searching loans by purpose
    create index(:loans, [:purpose])
    
    # Add composite index for efficient payment scheduling queries
    create index(:payments, [:loan_id, :due_date])
  end
end
