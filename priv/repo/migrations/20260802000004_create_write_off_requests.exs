defmodule MiwayCreditCore.Repo.Migrations.CreateWriteOffRequests do
  @moduledoc """
  Step 15: the missing front door onto the existing
  Lending.write_off_account/2, which previously had zero web-layer
  wiring, no permission gate, and no request/approval separation at
  all — callable by any code with just an admin_id. Real
  maker-checker, same guard as RestructuringRequest. Approval calls
  through to the existing write_off_account/2 rather than duplicating
  its balance-zeroing/ledger-posting logic.
  """

  use Ecto.Migration

  def change do
    create table(:write_off_requests, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :organisation_id, references(:organisations, type: :binary_id), null: false
      add :loan_account_id, references(:loan_accounts, type: :binary_id), null: false
      add :requested_by_id, references(:users), null: false
      add :requested_amount, :decimal, null: false
      add :reason, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :decided_by_id, references(:users)
      add :decided_at, :utc_datetime
      add :decision_notes, :string

      timestamps()
    end

    create index(:write_off_requests, [:loan_account_id])
    create index(:write_off_requests, [:status])
  end
end
