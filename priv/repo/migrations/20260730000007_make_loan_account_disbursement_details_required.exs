defmodule MiwayCreditCore.Repo.Migrations.MakeLoanAccountDisbursementDetailsRequired do
  use Ecto.Migration

  def change do
    alter table(:loan_accounts) do
      modify :contract_reference, :string, null: false
      modify :disbursement_method, :string, null: false
    end
  end
end
