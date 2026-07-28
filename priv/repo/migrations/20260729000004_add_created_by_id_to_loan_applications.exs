defmodule MiwayCreditCore.Repo.Migrations.AddCreatedByIdToLoanApplications do
  use Ecto.Migration

  # Nullable, unlike organisation_id's pattern — this is genuinely
  # optional information about who submitted an application (used for
  # maker-checker: the approver can't be the submitter), not a
  # structural invariant every row must satisfy.
  def change do
    alter table(:loan_applications) do
      add :created_by_id, references(:users)
    end
  end
end
