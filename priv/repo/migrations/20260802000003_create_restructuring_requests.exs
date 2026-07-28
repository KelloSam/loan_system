defmodule MiwayCreditCore.Repo.Migrations.CreateRestructuringRequests do
  @moduledoc """
  Step 15: term-extension-only restructuring (a smaller-payment ask
  and a more-time ask are the same lever on a fixed-rate amortized
  loan). Real maker-checker — approver can't be the requester, same
  guard Applications.check_separation_of_duties/3 already uses.
  """

  use Ecto.Migration

  def change do
    create table(:restructuring_requests, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :organisation_id, references(:organisations, type: :binary_id), null: false
      add :loan_account_id, references(:loan_accounts, type: :binary_id), null: false
      add :requested_by_id, references(:users), null: false
      add :additional_term_months, :integer, null: false
      add :reason, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :decided_by_id, references(:users)
      add :decided_at, :utc_datetime
      add :decision_notes, :string

      timestamps()
    end

    create index(:restructuring_requests, [:loan_account_id])
    create index(:restructuring_requests, [:status])
  end
end
