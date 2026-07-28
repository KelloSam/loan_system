defmodule MiwayCreditCore.Repo.Migrations.AddAssessmentAndDisbursementToLoanApplications do
  @moduledoc """
  Adds the two new decision points Step 9's state machine needs:
  assessment (pending -> under_review, staff review before a decision
  can be made) and disbursement (approved -> disbursed, now a
  separate step from the approve decision itself — see
  MiwayCreditCore.Applications.disburse_application/2).
  """

  use Ecto.Migration

  def change do
    alter table(:loan_applications) do
      add :assessed_at, :utc_datetime
      add :assessed_by_id, references(:users)
      add :assessment_notes, :text

      add :disbursed_at, :utc_datetime
      add :disbursed_by_id, references(:users)
    end
  end
end
