defmodule MiwayCreditCore.Repo.Migrations.MakeLoanProductIdRequired do
  use Ecto.Migration

  def change do
    alter table(:loan_applications) do
      modify :loan_product_id, :binary_id, null: false
    end

    alter table(:loan_accounts) do
      modify :loan_product_id, :binary_id, null: false
      modify :interest_method, :string, null: false
    end
  end
end
