defmodule MiwayCreditCore.Repo.Migrations.CreatePromisesToPay do
  @moduledoc """
  Step 15: evaluated by the existing ArrearsScheduler's periodic tick
  (Collections.evaluate_promises/0) rather than a second background
  process — a pending promise past its promised_date is marked kept
  if a posted payment >= promised_amount arrived since, else broken.
  """

  use Ecto.Migration

  def change do
    create table(:promises_to_pay, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :organisation_id, references(:organisations, type: :binary_id), null: false
      add :collection_case_id, references(:collection_cases, type: :binary_id), null: false
      add :promised_amount, :decimal, null: false
      add :promised_date, :date, null: false
      add :status, :string, null: false, default: "pending"
      add :recorded_by_id, references(:users), null: false
      add :evaluated_at, :utc_datetime

      timestamps()
    end

    create index(:promises_to_pay, [:collection_case_id])
    create index(:promises_to_pay, [:status])
  end
end
