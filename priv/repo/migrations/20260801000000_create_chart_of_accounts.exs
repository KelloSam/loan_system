defmodule MiwayCreditCore.Repo.Migrations.CreateChartOfAccounts do
  @moduledoc """
  Step 14: the chart of accounts backing the new double-entry general
  ledger — a small fixed set per organisation (see
  Accounting.GeneralLedger.seed_chart_of_accounts/1), not user-editable
  in this pass.
  """

  use Ecto.Migration

  def change do
    create table(:accounts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :organisation_id, references(:organisations, type: :binary_id), null: false
      add :code, :string, null: false
      add :name, :string, null: false
      add :account_type, :string, null: false

      timestamps()
    end

    create unique_index(:accounts, [:organisation_id, :code])
  end
end
