defmodule MiwayCreditCore.Repo.Migrations.AddApprovalWorkflowFieldsToLoanApplications do
  @moduledoc """
  conditions/conditions_cleared_at back a conditional approval —
  disburse_application/2 refuses until conditions_cleared_at is set.
  "referred" itself needs no new column, just a new entry in
  LoanApplication's existing @statuses list (already a plain string
  column with app-level validate_inclusion).
  """

  use Ecto.Migration

  def change do
    alter table(:loan_applications) do
      add :conditions, :text
      add :conditions_cleared_at, :utc_datetime
    end
  end
end
